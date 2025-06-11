// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/BaseSetup.sol";

abstract contract NewBaseIntegrationTest is BaseSetup {
    address public harvester = makeAddr("Harvester");

    /// @notice Deployed reward vaults for each gauge.
    RewardVault[] public rewardVaults;

    /// @notice Deployed reward receivers for each gauge.
    RewardReceiver[] public rewardReceivers;

    /// @notice Deposit tokens for each gauge.
    address[] public depositTokens;

    /// @notice Gauge addresses being tested.
    address[] public gauges;

    function test_complete_protocol_lifecycle(uint256[] memory _baseAmounts) public {
        vm.assume(_baseAmounts.length == gauges.length);
    }
}
