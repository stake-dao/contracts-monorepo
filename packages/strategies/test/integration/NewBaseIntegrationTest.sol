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

    /// @notice Mapping of reward vault to harvestable rewards.
    mapping(address => uint256) public rewardVaultToHarvestableRewards;

    /// @notice Gauge address being tested.
    address[] public gauges;

    constructor(address[] memory _gauges) {
        gauges = _gauges;
    }

    function test_complete_protocol_lifecycle(AccountPosition[] memory _accountPositions) public {
        /// 0. Deploy the RewardVaults.
        (rewardVaults, rewardReceivers) = deployRewardVaults();

        /// 1. Assert that the deployment is valid.
        assertDeploymentValid(rewardVaults, rewardReceivers);

        RewardVault rewardVault;
        RewardReceiver rewardReceiver;
        AccountPosition memory accountPosition;

        address gauge;

        for (uint256 i = 0; i < _accountPositions.length; i++) {
            accountPosition = _accountPositions[i];

            /// 2. Validate the account position.
            _validateAccountPositions(accountPosition);

            gauge = gauges[accountPosition.gaugeIndex];
            rewardVault = rewardVaults[accountPosition.gaugeIndex];
            rewardReceiver = rewardReceivers[accountPosition.gaugeIndex];

            /// 3. Deposit the amount into the vault.
            deposit(rewardVault, accountPosition.account, accountPosition.baseAmount);

            /// 4. Assertions
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

            assertEq(
                IStrategy(strategy).balanceOf(gauge),
                rewardVault.totalSupply(),
                "Expected strategy balance to be equal to total supply"
            );

            /// 5. Simulate rewards.
            simulateRewards(rewardVault);

            /// 6. Store the harvestable rewards for the vault for future assertions.
            rewardVaultToHarvestableRewards[address(rewardVault)] = getHarvestableRewards(rewardVault);

            /// 7. Skip 1 day.
            skip(1 days);

            // /// 8. Additional deposits.
            // deposit(rewardVault, accountPosition.account, accountPosition.additionalAmount);

            // /// 9. Assertions
            // assertEq(
            // rewardVault.balanceOf(accountPosition.account),
            // accountPosition.baseAmount + accountPosition.additionalAmount,
            // "Expected account balance to be equal to base amount plus additional amount"
            // );

            // assertGe(
            // rewardVault.totalSupply(),
            // accountPosition.baseAmount + accountPosition.additionalAmount,
            // "Expected total supply to be greater than or equal to base amount plus additional amount"
            // );

            // assertEq(
            // IStrategy(gauge).balanceOf(gauge),
            // rewardVault.totalSupply(),
            // "Expected strategy balance to be equal to total supply"
            // );
        }
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDABLE FUNCTIONS
    //////////////////////////////////////////////////////

    function deployRewardVaults()
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

    /// @notice Gets the harvestable rewards for the given vault.
    function getHarvestableRewards(RewardVault vault) internal view returns (uint256) {}

    /// @notice Simulates rewards for the given vault.
    function simulateRewards(RewardVault vault) internal virtual {}

    //////////////////////////////////////////////////////
    /// --- TEST HELPERS
    //////////////////////////////////////////////////////

    function deposit(RewardVault rewardVault, address account, uint256 amount) internal {
        /// 1. Get the asset address.
        address asset = rewardVault.asset();

        /// 2. Deal the amount to the account.
        deal(asset, account, amount);

        /// 3. Approve the asset to be spent by the vault.
        vm.startPrank(account);
        IERC20(asset).approve(address(rewardVault), amount);

        /// 4. Deposit
        rewardVault.deposit(amount, account);
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
