// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/BaseSetup.sol";

import {Factory} from "src/Factory.sol";

abstract contract NewBaseIntegrationTest is BaseSetup {
    address public harvester = makeAddr("Harvester");

    struct AccountPosition {
        address account;
        uint256 baseAmount;
        uint256 additionalAmount;
        uint256 gaugeIndex;
    }

    /// @notice Deployed reward vaults for each gauge.
    RewardVault[] public rewardVaults;

    /// @notice Deployed reward receivers for each gauge.
    RewardReceiver[] public rewardReceivers;

    /// @notice Gauge address being tested.
    address[] public gauges;

    function test_complete_protocol_lifecycle(AccountPosition[] memory _accountPositions) public {
        /// 0. Deploy the vaults.
        (rewardVaults, rewardReceivers) = _deployVaults();

        /// 1. Assert that the deployment is valid.
        assertDeploymentValid(rewardVaults, rewardReceivers);

        RewardVault rewardVault;
        RewardReceiver rewardReceiver;
        AccountPosition memory accountPosition;
        for (uint256 i = 0; i < _accountPositions.length; i++) {
            accountPosition = _accountPositions[i];

            /// 1. Validate the account position.
            _validateAccountPositions(accountPosition);

            rewardVault = rewardVaults[accountPosition.gaugeIndex];
            rewardReceiver = rewardReceivers[accountPosition.gaugeIndex];

            /// 2. Deposit the amount into the vault.
            deposit(rewardVault, accountPosition);

            assertEq(
                rewardVault.balanceOf(accountPosition.account),
                accountPosition.baseAmount,
                "Expected account balance to be equal to deposited amount"
            );

            assertGe(
                rewardVault.totalSupply(),
                accountPosition.baseAmount,
                "Expected total supply to be greater than or equal to deposited amount"
            );
        }
    }

    constructor(address[] memory _gauges) {
        gauges = _gauges;
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDABLE FUNCTIONS
    //////////////////////////////////////////////////////

    function _deployVaults()
        internal
        virtual
        returns (RewardVault[] memory vaults, RewardReceiver[] memory receivers)
    {
        /// Deploy the vaults.
        vaults = new RewardVault[](gauges.length);
        receivers = new RewardReceiver[](gauges.length);

        for (uint256 i = 0; i < gauges.length; i++) {
            address gauge = gauges[i];

            /// Deploy the vault and receiver.
            (address vault, address receiver) = Factory(factory).createVault(gauge);

            vaults[i] = RewardVault(vault);
            receivers[i] = RewardReceiver(receiver);
        }
    }

    //////////////////////////////////////////////////////
    /// --- TEST HELPERS
    //////////////////////////////////////////////////////

    function deposit(RewardVault rewardVault, AccountPosition memory accountPosition) internal {
        /// 1. Get the asset address.
        address asset = rewardVault.asset();

        /// 2. Deal the amount to the account.
        deal(asset, accountPosition.account, accountPosition.baseAmount);

        /// 3. Approve the asset to be spent by the vault.
        vm.startPrank(accountPosition.account);
        IERC20(asset).approve(address(rewardVault), accountPosition.baseAmount);

        /// 4. Deposit
        rewardVault.deposit(accountPosition.baseAmount, accountPosition.account);
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////
    /// --- VALIDATION HELPERS
    //////////////////////////////////////////////////////

    function assertDeploymentValid(RewardVault[] memory vaults, RewardReceiver[] memory receivers) internal pure {
        RewardVault vault;
        RewardReceiver receiver;
        for (uint256 i = 0; i < vaults.length; i++) {
            vault = vaults[i];
            receiver = receivers[i];
        }
    }

    function _validateAccountPositions(AccountPosition memory accountPosition) internal view {
        /// Assert that the gauge index is within the bounds of the gauges array.
        accountPosition.gaugeIndex = bound(accountPosition.gaugeIndex, 0, gauges.length - 1);

        /// Get the gauge address.
        vm.assume(accountPosition.baseAmount > 1e18);
        vm.assume(accountPosition.additionalAmount > 1e18);

        /// Get the max amount of base tokens that can be deposited into the gauge.
        // Limit the max amount to 50% of the total supply to avoid overflows.
        address gauge = gauges[accountPosition.gaugeIndex];
        uint256 maxAmount = IERC20(gauge).totalSupply() / 2;

        vm.assume(accountPosition.baseAmount < maxAmount);
        /// Just enough to have a non-zero additional amount.
        vm.assume(accountPosition.additionalAmount < accountPosition.baseAmount);
    }
}
