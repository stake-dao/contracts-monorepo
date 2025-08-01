import os, json
import time
import random
import concurrent.futures
import argparse
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

BOOSTER = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"

booster_abi = [
    {
        "inputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "name": "poolInfo",
        "outputs": [
            {"internalType": "address", "name": "lptoken", "type": "address"},
            {"internalType": "address", "name": "token", "type": "address"},
            {"internalType": "address", "name": "gauge", "type": "address"},
            {"internalType": "address", "name": "crvRewards", "type": "address"},
            {"internalType": "address", "name": "stash", "type": "address"},
            {"internalType": "bool", "name": "shutdown", "type": "bool"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    {
        "inputs": [],
        "name": "poolLength",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    },
]

is_killed_abi = [
    {
        "inputs": [],
        "name": "is_killed",
        "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
        "stateMutability": "view",
        "type": "function",
    }
]

# Initialize Web3 with multiple RPC endpoints for load balancing
RPC_ENDPOINTS = [
    "https://eth.llamarpc.com",
    "https://ethereum.publicnode.com",
    "https://rpc.ankr.com/eth",
]

# Add Alchemy if key is available
alchemy_key = os.getenv("ALCHEMY_KEY")
if alchemy_key and alchemy_key.strip():
    RPC_ENDPOINTS.append(f"https://eth-mainnet.g.alchemy.com/v2/{alchemy_key}")

# Ensure we have at least one endpoint
if not RPC_ENDPOINTS:
    print("Warning: No RPC endpoints available. Using a default endpoint.")
    RPC_ENDPOINTS = ["https://eth.llamarpc.com"]

print(f"Using {len(RPC_ENDPOINTS)} RPC endpoints for load balancing")

# Create a Web3 provider for each endpoint
web3_providers = [Web3(Web3.HTTPProvider(endpoint)) for endpoint in RPC_ENDPOINTS]

# Query all pools on Convex.
booster_contracts = [
    w3.eth.contract(address=BOOSTER, abi=booster_abi) for w3 in web3_providers
]


def get_pool_info_with_retry(pid, max_retries=5):
    """Get info for a single pool by pid with retry logic"""
    retries = 0
    backoff_time = 0.1  # Start with 100ms backoff

    while retries < max_retries:
        try:
            # Select a random provider to distribute load
            provider_index = random.randrange(len(web3_providers))
            w3 = web3_providers[provider_index]
            booster = booster_contracts[provider_index]

            # Add a small random delay to avoid request bursts
            time.sleep(random.uniform(0.05, 0.2))

            pool = booster.functions.poolInfo(pid).call()
            gauge = pool[2]
            isShutdown = pool[5]

            # Check if gauge is killed
            try:
                isKilled = (
                    w3.eth.contract(address=gauge, abi=is_killed_abi)
                    .functions.is_killed()
                    .call()
                )
            except Exception:
                # If we can't determine if it's killed, assume it's not
                isKilled = False

            if isShutdown or isKilled:
                return None

            return {"pid": pid, "gauge": gauge}

        except Exception as e:
            retries += 1
            if "Too Many Requests" in str(e) or "429" in str(e):
                # Exponential backoff with jitter for rate limit errors
                backoff_time = min(backoff_time * 2, 5)  # Cap at 5 seconds
                sleep_time = backoff_time + random.uniform(0, 1)
                print(
                    f"Rate limited for pool {pid}, retrying in {sleep_time:.2f}s (attempt {retries}/{max_retries})"
                )
                time.sleep(sleep_time)
            elif retries >= max_retries:
                print(f"Error fetching pool {pid} after {max_retries} retries: {e}")
                return None
            else:
                # For other errors, retry with a small delay
                time.sleep(random.uniform(0.2, 0.5))

    return None


def get_all_pools():
    """Get all pools using concurrent processing with rate limiting"""
    start_time = time.time()

    # Use the first provider to get pool length
    pool_length = booster_contracts[0].functions.poolLength().call()
    print(f"Total pools to check: {pool_length}")

    # Use ThreadPoolExecutor for concurrent requests, but with fewer workers
    pool_list = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        # Submit all tasks
        future_to_pid = {
            executor.submit(get_pool_info_with_retry, pid): pid
            for pid in range(pool_length)
        }

        # Process results as they complete
        for i, future in enumerate(concurrent.futures.as_completed(future_to_pid)):
            if i % 20 == 0:
                print(f"Processed {i}/{pool_length} pools...")

            result = future.result()
            if result:
                pool_list.append(result)

    end_time = time.time()
    print(
        f"Fetched {len(pool_list)} active pools in {end_time - start_time:.2f} seconds"
    )
    return pool_list


def get_specific_pools(pids):
    """Get specific pools by their PIDs"""
    start_time = time.time()

    print(f"Fetching {len(pids)} specific pools: {pids}")

    # Use ThreadPoolExecutor for concurrent requests
    pool_list = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        # Submit tasks for specific PIDs
        future_to_pid = {
            executor.submit(get_pool_info_with_retry, pid): pid for pid in pids
        }

        # Process results as they complete
        for i, future in enumerate(concurrent.futures.as_completed(future_to_pid)):
            if i % 5 == 0:
                print(f"Processed {i}/{len(pids)} pools...")

            result = future.result()
            if result:
                pool_list.append(result)

    end_time = time.time()
    print(
        f"Fetched {len(pool_list)} active pools in {end_time - start_time:.2f} seconds"
    )
    return pool_list


def filter_pools(pools, count=None, from_start=True):
    """Filter pools based on count and direction"""
    if not count or count >= len(pools):
        return pools

    # Sort pools by PID
    sorted_pools = sorted(pools, key=lambda x: x["pid"])

    if from_start:
        # Return pools from the start (lowest PIDs)
        return sorted_pools[:count]
    else:
        # Return pools from the end (highest PIDs)
        return sorted_pools[-count:]


def generate_solidity_file(pools, output_file=None):
    # Sort pools by PID in descending order
    pools = sorted(pools, key=lambda x: x["pid"], reverse=True)

    # Start building the Solidity file content
    solidity_content = """// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import "test/integration/curve/CurveIntegration.t.sol";
import "test/integration/curve/CurveFactory.t.sol";

// @notice Selected Convex pool PIDs sorted by PID (highest to lowest)
// @dev Each integration test requires two PIDs to test multi-gauge functionality
// @dev Make sure both gauges are properly initialized with _setupGauge in setUp
"""

    # Add each pool as a constant with a comment about its gauge
    for pool in pools:
        pid = pool["pid"]
        gauge_address = pool["gauge"]
        constant_name = f"CONVEX_POOL_{pid}_PID"

        solidity_content += f"""
uint256 constant {constant_name} = {pid};
"""

    # Create test contracts by pairing pools
    # Each integration test needs two PIDs
    for i in range(0, len(pools) - 1, 2):
        pid1 = pools[i]["pid"]
        pid2 = pools[i + 1]["pid"] if i + 1 < len(pools) else pools[0]["pid"]
        
        constant_name1 = f"CONVEX_POOL_{pid1}_PID"
        constant_name2 = f"CONVEX_POOL_{pid2}_PID"
        
        # Create factory test for pid1
        solidity_content += f"""
contract {constant_name1}_Factory_Test is CurveFactoryTest({constant_name1}) {{}}

// Integration test using {pid1} and {pid2}
contract {constant_name1}_Integration_Test is CurveIntegrationTest({constant_name1}, {constant_name2}) {{}}
"""

        # Add factory test for pid2 only if not the last pool paired with the first
        if i + 1 < len(pools):
            solidity_content += f"""
contract {constant_name2}_Factory_Test is CurveFactoryTest({constant_name2}) {{}}
"""

    # For odd number of pools, ensure the last one has a factory test
    if len(pools) % 2 != 0:
        last_pid = pools[-1]["pid"]
        solidity_content += f"""
// Last pool factory test
contract CONVEX_POOL_{last_pid}_PID_Factory_Test is CurveFactoryTest(CONVEX_POOL_{last_pid}_PID) {{}}
"""

    # Create the directory if it doesn't exist
    output_dir = "test/integration/curve"
    os.makedirs(output_dir, exist_ok=True)

    # Set default output file if not provided
    if not output_file:
        output_file = os.path.join(output_dir, "ConvexPools.t.sol")
    else:
        # Ensure the output file has the correct extension
        if not output_file.endswith(".sol"):
            output_file += ".t.sol"
        output_file = os.path.join(output_dir, output_file)

    with open(output_file, "w") as f:
        f.write(solidity_content)

    print(f"Generated Solidity file at {output_file}")
    print(f"Included {len(pools)} pools with PIDs: {[p['pid'] for p in pools]}")
    
    # Print information about pool pairings for integration tests
    print("\nPool pairings for integration tests:")
    for i in range(0, len(pools) - 1, 2):
        pid1 = pools[i]["pid"]
        pid2 = pools[i + 1]["pid"] if i + 1 < len(pools) else pools[0]["pid"]
        print(f"  - Integration test with PIDs {pid1} and {pid2}")


def generate_solidity_files_by_group(pools, group_size=10, output_prefix="ConvexPools"):
    """Generate multiple Solidity files, each containing a group of pools"""
    # Sort pools by PID in descending order
    pools = sorted(pools, key=lambda x: x["pid"], reverse=True)
    
    # Split pools into groups
    pool_groups = [pools[i:i + group_size] for i in range(0, len(pools), group_size)]
    
    print(f"Splitting {len(pools)} pools into {len(pool_groups)} groups of max {group_size} pools each")
    
    for group_index, group_pools in enumerate(pool_groups):
        output_file = f"{output_prefix}_Group{group_index+1}.t.sol"
        
        # Generate Solidity file for this group
        generate_solidity_file(group_pools, output_file)
        
        print(f"Generated group {group_index+1} with {len(group_pools)} pools")


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Generate Solidity test files for Convex pools with dual-PID test structure"
    )

    # Create a mutually exclusive group for pool selection methods
    selection_group = parser.add_mutually_exclusive_group()

    selection_group.add_argument("--count", type=int, help="Number of pools to include")

    selection_group.add_argument(
        "--pids", type=int, nargs="+", help="Specific pool IDs to include"
    )

    parser.add_argument(
        "--reverse",
        action="store_true",
        help="Select pools from the end (highest PIDs) instead of from the start",
    )

    parser.add_argument(
        "--output", type=str, help="Output file name (default: ConvexPools.t.sol)"
    )
    
    parser.add_argument(
        "--split-groups", 
        type=int, 
        help="Split pools into multiple files with specified number of pools per file"
    )

    return parser.parse_args()


def main():
    args = parse_arguments()
    start_time = time.time()

    if args.pids:
        # Get specific pools by PIDs
        pools = get_specific_pools(args.pids)
    elif args.count:
        # Get pool length first
        pool_length = booster_contracts[0].functions.poolLength().call()
        print(f"Total pools available: {pool_length}")

        # Determine which PIDs to fetch based on count and direction
        if args.reverse:
            # Get pools from the end (highest PIDs)
            start_pid = max(0, pool_length - args.count)
            pids_to_fetch = list(range(start_pid, pool_length))
        else:
            # Get pools from the start (lowest PIDs)
            pids_to_fetch = list(range(min(args.count, pool_length)))

        print(
            f"Fetching {len(pids_to_fetch)} pools from {'end' if args.reverse else 'start'}"
        )
        pools = get_specific_pools(pids_to_fetch)
    else:
        # Get all pools
        pools = get_all_pools()

    if not pools:
        print("No valid pools found. Exiting.")
        return
        
    # Check if we need to split output into multiple files
    if args.split_groups and args.split_groups > 0:
        generate_solidity_files_by_group(pools, args.split_groups, 
                                        args.output or "ConvexPools")
    else:
        # Generate a single Solidity file
        generate_solidity_file(pools, args.output)

    end_time = time.time()
    print(f"Total execution time: {end_time - start_time:.2f} seconds")


if __name__ == "__main__":
    main()
