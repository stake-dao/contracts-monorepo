// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";
import {CurveLocker} from "address-book/src/CurveEthereum.sol";
import {Safe, SafeLibrary, SafeProxy} from "test/utils/SafeLibrary.sol";

/// @title GetLocker
/// @notice Deployment script for creating the Curve Locker Safe at a deterministic address
/// @dev This script deploys a Safe multisig wallet at the expected Curve Locker address by manipulating the deployer's nonce
contract GetLocker is Script {
    /// @notice Protocol identifier for Curve
    bytes4 internal constant PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice Admin address for the locker
    address public constant ADMIN = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    /// @notice Deployer address
    address public constant DEPLOYER = 0xb36a0671B3D49587236d7833B01E79798175875f;

    /// @notice Target nonce for deterministic deployment
    uint256 public constant NONCE_TARGET = 84;

    /// @notice Owner address for the Safe multisig
    address public constant OWNER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    /// @notice Main deployment function
    function run() public {
        console.log("Starting Curve Locker Safe deployment...");
        console.log("Deployer:", DEPLOYER);
        console.log("Target nonce:", NONCE_TARGET);
        console.log("Expected locker address:", address(CurveLocker.LOCKER));

        vm.createSelectFork("base");
        vm.startBroadcast(DEPLOYER);

        // Prepare owners array
        address[] memory owners = new address[](1);
        owners[0] = OWNER;

        // Increase nonce to target value
        _increaseNonceToTarget();

        // Deploy Safe proxy
        address safe = address(_deploySafeProxy(owners));

        console.log("Final nonce:", vm.getNonce(DEPLOYER));
        console.log("Safe deployed at:", safe);

        vm.stopBroadcast();
    }

    /// @notice Increases the deployer's nonce to the target value
    /// @dev Makes empty calls to increase the nonce count
    function _increaseNonceToTarget() internal {
        uint256 currentNonce = vm.getNonce(DEPLOYER);
        console.log("Current nonce:", currentNonce);

        while (currentNonce < NONCE_TARGET) {
            // Empty call to increase nonce
            (bool success,) = address(DEPLOYER).call("");
            require(success, "Call failed");

            currentNonce = vm.getNonce(DEPLOYER);
            console.log("Nonce increased to:", currentNonce);
        }
    }

    /// @notice Deploys a new Safe proxy with the specified owners
    /// @param owners Array of owner addresses for the Safe
    /// @return proxy The deployed Safe proxy contract
    function _deploySafeProxy(address[] memory owners) internal returns (SafeProxy proxy) {
        // Get the initializer for the Safe
        bytes memory initializer = SafeLibrary.getInitializer(owners, 1);

        // Deploy Safe proxy using CREATE
        bytes memory deploymentData =
            abi.encodePacked(type(SafeProxy).creationCode, uint256(uint160(SafeLibrary.SAFE_L2_SINGLETON)));

        assembly {
            proxy := create(0x0, add(0x20, deploymentData), mload(deploymentData))
        }

        // Verify deployment
        require(address(proxy) != address(0), "Create call failed");
        require(address(proxy).code.length > 0, "Proxy is not deployed");
        require(address(proxy) == address(CurveLocker.LOCKER), "Proxy is not the Curve Locker");

        // Initialize the Safe proxy
        if (initializer.length > 0) {
            assembly {
                if eq(call(gas(), proxy, 0, add(initializer, 0x20), mload(initializer), 0, 0), 0) { revert(0, 0) }
            }
        }
    }
}
