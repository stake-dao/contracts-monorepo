// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "forge-std/src/Test.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockAllocator} from "test/mocks/MockAllocator.sol";
import {MockGateway} from "test/mocks/MockGateway.sol";
import {MockLocker} from "test/mocks/MockLocker.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";

/// @title BaseTest
/// @notice Base test contract with common utilities and setup for all tests
abstract contract BaseTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    // Common addresses used across tests
    address internal owner = address(this);
    address internal vault = makeAddr("vault");
    bytes4 internal protocolId = bytes4(bytes("fake_id"));

    // Common mock contracts
    ERC20Mock internal rewardToken;
    ERC20Mock internal stakingToken;
    MockLocker internal locker;
    MockGateway internal gateway;
    MockRegistry internal registry;
    MockAllocator internal allocator;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        /// Setup the reward and staking tokens
        rewardToken = new ERC20Mock("Reward Token", "RT", 18);
        stakingToken = new ERC20Mock("Staking Token", "ST", 18);

        /// Setup the gateway
        locker = new MockLocker();
        gateway = new MockGateway(address(locker));
        /// Setup the registry and allocator
        registry = new MockRegistry();
        allocator = new MockAllocator();

        // Mock the registry `assets` function used to fetch the vault's asset
        bytes[] memory mocks = new bytes[](1);
        mocks[0] = abi.encode(address(rewardToken));
        vm.mockCalls(address(registry), abi.encodeWithSelector(MockRegistry.asset.selector), mocks);

        /// Label common contracts
        vm.label({account: address(locker), newLabel: "Locker"});
        vm.label({account: address(gateway), newLabel: "Gateway"});
        vm.label({account: address(registry), newLabel: "Registry"});
        vm.label({account: address(allocator), newLabel: "Allocator"});
        vm.label({account: address(rewardToken), newLabel: "Reward Token"});
        vm.label({account: address(stakingToken), newLabel: "Staking Token"});
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    //////////////////////////////////////////////////////////////////////////*/
    /// @notice Utility function to ensure a fuzzed address has not been previously labeled
    function _assumeUnlabeledAddress(address fuzzedAddress) internal view {
        vm.assume(bytes10(bytes(vm.getLabel(fuzzedAddress))) == bytes10(bytes("unlabeled:")));
    }

    /// @notice Helper to deploy code to a specific address (for harness contracts)
    function _deployHarnessCode(string memory artifactPath, bytes memory constructorArgs, address target) internal {
        deployCodeTo(artifactPath, constructorArgs, target);
    }

    /// @notice Helper to deploy code to a specific address (for harness contracts)
    function _deployHarnessCode(string memory artifactPath, address target) internal {
        deployCodeTo(artifactPath, target);
    }

    /// @notice Helper to override a storage slot by hand. Useful for overriding mappings
    /// @param target The target contract address
    /// @param signature The signature of the function to override
    /// @param value The value to set the storage slot to
    /// @param key The key of the storage slot to override
    function _cheat_override_storage(address target, string memory signature, bytes32 value, bytes32 key) internal {
        stdstore.target(target).sig(signature).with_key(key).checked_write(value);
    }

    /// @notice Helper to override a storage slot by hand. Useful for overriding non-mapping storage slots
    /// @param target The target contract address
    /// @param signature The signature of the function to override
    /// @param value The value to set the storage slot to
    function _cheat_override_storage(address target, string memory signature, bytes32 value) internal {
        stdstore.target(target).sig(signature).checked_write(value);
    }
}
