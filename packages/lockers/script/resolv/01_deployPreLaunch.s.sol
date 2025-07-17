// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {CommonUniversal} from "@address-book/src/CommonUniversal.sol";
import {ResolvProtocol} from "@address-book/src/ResolvEthereum.sol";
import {PreLaunchDeploy} from "script/common/PreLaunch/01_deploy.s.sol";

/// @title ResolvPreLaunchDeploy
/// @notice This script deploys the Resolv pre-launch infrastructure
/// @dev Deploy using:
///      - Ledger: forge script ResolvPreLaunchDeploy --rpc-url <RPC_URL> --ledger --broadcast
///      - Private key: forge script ResolvPreLaunchDeploy --rpc-url <RPC_URL> --private-key <KEY> --broadcast
/// @custom:contact contact@stakedao.org
contract ResolvPreLaunchDeploy is PreLaunchDeploy {
    function run()
        external
        override
        returns (address sdToken, address gauge, address preLaunchLocker, address locker)
    {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(CommonUniversal.DEPLOYER_1);
        // Use the Resolv token address from the address book
        address token = ResolvProtocol.RESOLV;

        // Resolv-specific configuration
        string memory name = "Stake DAO Resolv";
        string memory symbol = "sdRESOLV";
        uint256 customForceCancelDelay = 0; // Use default delay

        // Deploy the pre-launch infrastructure
        (sdToken, gauge, preLaunchLocker, locker) = _run(token, name, symbol, customForceCancelDelay);

        vm.stopBroadcast();
    }

    /// @notice Event emitted when contracts are deployed
    event Deployed(
        address indexed token, address indexed sdToken, address gauge, address preLaunchLocker, address locker
    );
}
