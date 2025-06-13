// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/BaseSetup.sol";

import {Factory} from "src/Factory.sol";

abstract contract BaseIntegrationTest is BaseSetup {
    using Math for uint256;

    uint256 public constant MAX_REWARDS = 100_000e18;
    uint256 public constant MAX_ACCOUNT_POSITIONS = 100;

    address public harvester = makeAddr("Harvester");

    struct AccountPosition {
        address account;
        uint256 baseAmount;
        uint256 additionalAmount;
        uint256 partialWithdrawAmount;
        uint256 gaugeIndex;
        address transferReceiver;
    }

    /// @notice Deployed reward vaults for each gauge.
    RewardVault[] public rewardVaults;

    /// @notice Deployed reward receivers for each gauge.
    RewardReceiver[] public rewardReceivers;

    /// @notice Total harvestable rewards.
    uint256 public totalHarvestableRewards;

    /// @notice Mapping of account to claimed rewards.
    mapping(address => uint256) public rewardVaultToHarvestableRewards;

    /// @notice Gauge address being tested.
    address[] public gauges;

    /// @notice Get the gauge addresses to test with
    /// @dev This function should be implemented by each integration test to provide its specific gauge addresses
    /// @return Array of gauge addresses to test with
    function getGauges() internal virtual returns (address[] memory) {
        revert("getGauges not implemented");
    }

    function test_complete_protocol_lifecycle() public {
        (AccountPosition[] memory _accountPositions, uint256[] memory _rewards) = _generateAccountPositionsAndRewards();

        /// 1. Deploy the RewardVaults.
        (rewardVaults, rewardReceivers) = deployRewardVaults();

        /// 2. Assert that the deployment is valid.
        assertDeploymentValid(rewardVaults, rewardReceivers);

        RewardVault rewardVault;
        RewardReceiver rewardReceiver;
        AccountPosition memory accountPosition;

        address gauge;

        for (uint256 i = 0; i < _accountPositions.length; i++) {
            accountPosition = _accountPositions[i];

            gauge = gauges[accountPosition.gaugeIndex];
            rewardVault = rewardVaults[accountPosition.gaugeIndex];
            rewardReceiver = rewardReceivers[accountPosition.gaugeIndex];

            /// 4. Deposit the amount into the vault.
            deposit(rewardVault, accountPosition.account, accountPosition.baseAmount);

            /// 5. Assertions
            assertEq(
                rewardVault.balanceOf(accountPosition.account),
                accountPosition.baseAmount,
                "1. Expected account balance to be equal to deposited amount"
            );

            assertGe(
                rewardVault.totalSupply(),
                accountPosition.baseAmount,
                "2. Expected total supply to be greater than or equal to deposited amount"
            );

            assertEq(
                IStrategy(strategy).balanceOf(gauge),
                rewardVault.totalSupply(),
                "3. Expected strategy balance to be equal to total supply"
            );

            /// 6. Simulate rewards.
            simulateRewards(rewardVault, _rewards[i]);

            /// 7. Store the harvestable rewards for the vault for future assertions.
            totalHarvestableRewards += _rewards[i];
            rewardVaultToHarvestableRewards[address(rewardVault)] += _rewards[i];

            /// 8. Skip 1 day.
            skip(1 days);

            /// 9. Additional deposits.
            deposit(rewardVault, accountPosition.account, accountPosition.additionalAmount);

            /// 10. Assertions
            assertEq(
                rewardVault.balanceOf(accountPosition.account),
                accountPosition.baseAmount + accountPosition.additionalAmount,
                "4. Expected account balance to be equal to base amount plus additional amount"
            );

            assertGe(
                rewardVault.totalSupply(),
                accountPosition.baseAmount + accountPosition.additionalAmount,
                "5. Expected total supply to be greater than or equal to base amount plus additional amount"
            );

            assertEq(
                IStrategy(strategy).balanceOf(gauge),
                rewardVault.totalSupply(),
                "6. Expected strategy balance to be equal to total supply after additional deposits"
            );
        }

        /// 10. Assert that the accountant has no rewards before harvest.
        assertEq(
            _balanceOf(rewardToken, address(accountant)), 0, "7. Expected accountant to have no rewards before harvest"
        );

        /// 11. Assert that the harvester has no rewards before harvest.
        assertEq(_balanceOf(rewardToken, harvester), 0, "8. Expected harvester to have no rewards before harvest");

        /// 12. Assert that the protocol fees accrued are 0.
        assertEq(accountant.protocolFeesAccrued(), 0, "9. Expected protocol fees accrued to be 0");

        /// 13. Harvest the rewards.
        harvest();

        uint256 expectedHarvesterBalance = totalHarvestableRewards.mulDiv(accountant.getHarvestFeePercent(), 1e18);
        uint256 expectedProtocolFeesAccrued = totalHarvestableRewards.mulDiv(accountant.getProtocolFeePercent(), 1e18);
        uint256 expectedAccountantBalance = totalHarvestableRewards - expectedHarvesterBalance;

        /// 14. Assert that the accountant has the correct balance.
        assertApproxEqRel(
            _balanceOf(rewardToken, address(accountant)),
            expectedAccountantBalance,
            0.001e18,
            "10. Expected accountant to have rewards after harvest with a 0.1% error"
        );

        /// 15. Assert that the harvester has the correct balance.
        assertApproxEqRel(
            _balanceOf(rewardToken, harvester),
            expectedHarvesterBalance,
            0.001e18,
            "11. Expected harvester to have rewards after harvest with a 0.1% error"
        );

        /// 16. Assert that the protocol fees accrued are the correct amount.
        assertApproxEqRel(
            accountant.protocolFeesAccrued(),
            expectedProtocolFeesAccrued,
            0.001e18,
            "12. Expected protocol fees accrued to be greater than 0 after harvest with a 0.1% error"
        );

        for (uint256 i = 0; i < _accountPositions.length; i++) {
            accountPosition = _accountPositions[i];

            gauge = gauges[accountPosition.gaugeIndex];
            rewardVault = rewardVaults[accountPosition.gaugeIndex];
            rewardReceiver = rewardReceivers[accountPosition.gaugeIndex];

            assertEq(
                _balanceOf(rewardToken, accountPosition.account),
                0,
                "Expected reward token balance to be 0 before claiming"
            );
            assertGt(
                accountant.getPendingRewards(address(rewardVault), accountPosition.account),
                0,
                "Expected pending rewards to be greater than 0 before claiming"
            );

            /// 17. Claim the rewards.
            claim(rewardVault, accountPosition.account);

            assertGt(
                _balanceOf(rewardToken, accountPosition.account),
                0,
                "13. Expected reward token balance to be greater than 0 after claiming"
            );
            assertEq(
                accountant.getPendingRewards(address(rewardVault), accountPosition.account),
                0,
                "14. Expected pending rewards to be 0 after claiming"
            );

            uint256 totalSupply = rewardVault.totalSupply();

            /// 18. Partial withdraw.
            withdraw(rewardVault, accountPosition.account, accountPosition.partialWithdrawAmount);

            assertGt(
                rewardVault.balanceOf(accountPosition.account),
                0,
                "15. Expected reward vault balance to be greater than 0 after partial withdraw"
            );

            assertEq(
                rewardVault.balanceOf(accountPosition.account),
                accountPosition.baseAmount + accountPosition.additionalAmount - accountPosition.partialWithdrawAmount,
                "16. Expected reward vault balance to be equal to base amount plus additional amount minus partial withdraw amount"
            );
            assertEq(
                rewardVault.totalSupply(),
                totalSupply - accountPosition.partialWithdrawAmount,
                "17. Expected reward vault total supply to be equal to total supply minus partial withdraw amount"
            );
            assertEq(
                IStrategy(strategy).balanceOf(gauge),
                rewardVault.totalSupply(),
                "18. Expected strategy balance to be equal to total supply after partial withdraw"
            );

            /// 19. Simulate additional rewards for share transfer test
            simulateRewards(rewardVault, _rewards[i] / 2);
        }

        skip(1 days);

        /// 20. Test share transfers
        // This tests that:
        // - Accrued rewards stay with the original account when shares are transferred
        // - New rewards (if any) accrue to the transfer receiver after the transfer
        // - Both accounts can claim their respective rewards
        for (uint256 i = 0; i < _accountPositions.length; i++) {
            accountPosition = _accountPositions[i];
            rewardVault = rewardVaults[accountPosition.gaugeIndex];

            uint256 remainingShares = rewardVault.balanceOf(accountPosition.account);
            if (remainingShares > 0) {
                // Transfer all remaining shares to transfer receiver
                transferShares(rewardVault, accountPosition.account, accountPosition.transferReceiver, remainingShares);

                assertEq(
                    rewardVault.balanceOf(accountPosition.account),
                    0,
                    "19. Expected account to have 0 shares after transfer"
                );
                assertEq(
                    rewardVault.balanceOf(accountPosition.transferReceiver),
                    remainingShares,
                    "20. Expected transfer receiver to have all transferred shares"
                );
            }
        }

        // Harvest after transfers
        harvest();

        /// 21. Verify rewards follow share ownership
        for (uint256 i = 0; i < _accountPositions.length; i++) {
            accountPosition = _accountPositions[i];
            rewardVault = rewardVaults[accountPosition.gaugeIndex];

            // Original accounts should still have their accrued rewards from before the transfer
            uint256 originalAccountPendingRewards =
                accountant.getPendingRewards(address(rewardVault), accountPosition.account);
            assertGt(
                originalAccountPendingRewards,
                0,
                "21. Expected original account to still have pending rewards from before transfer"
            );

            // Claim rewards as original account
            claim(rewardVault, accountPosition.account);
            assertGt(
                _balanceOf(rewardToken, accountPosition.account),
                0,
                "22. Expected original account to have claimed their accrued rewards"
            );

            // Transfer receivers may or may not have pending rewards depending on if new rewards were generated
            uint256 pendingRewards =
                accountant.getPendingRewards(address(rewardVault), accountPosition.transferReceiver);
            if (pendingRewards > 0) {
                // Claim as transfer receiver if they have rewards
                claim(rewardVault, accountPosition.transferReceiver);

                assertGt(
                    _balanceOf(rewardToken, accountPosition.transferReceiver),
                    0,
                    "23. Expected transfer receiver to have claimed rewards when available"
                );
            }

            // Transfer shares back to original account
            uint256 transferReceiverShares = rewardVault.balanceOf(accountPosition.transferReceiver);
            if (transferReceiverShares > 0) {
                transferShares(
                    rewardVault, accountPosition.transferReceiver, accountPosition.account, transferReceiverShares
                );
            }

            // Final withdrawal - withdraw all remaining shares
            uint256 finalBalance = rewardVault.balanceOf(accountPosition.account);
            if (finalBalance > 0) {
                withdraw(rewardVault, accountPosition.account, finalBalance);

                assertEq(
                    rewardVault.balanceOf(accountPosition.account),
                    0,
                    "25. Expected account to have 0 shares after final withdrawal"
                );
            }
        }

        // Verify all vaults are empty
        for (uint256 i = 0; i < rewardVaults.length; i++) {
            assertEq(
                rewardVaults[i].totalSupply(), 0, "26. Expected vault to have 0 total supply after all withdrawals"
            );
            assertEq(
                IStrategy(strategy).balanceOf(gauges[i]),
                0,
                "27. Expected strategy to have 0 balance after all withdrawals"
            );
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

    /// @notice Simulates rewards for the given vault.
    function simulateRewards(RewardVault vault, uint256 amount) internal virtual {}

    function getHarvestableRewards(RewardVault vault) internal virtual returns (uint256) {}

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

    function harvest() internal {
        bytes[] memory harvestData = new bytes[](gauges.length);

        vm.prank(harvester);
        accountant.harvest(gauges, harvestData, harvester);
    }

    function claim(RewardVault rewardVault, address account) internal {
        address[] memory accountGauges = new address[](1);
        accountGauges[0] = rewardVault.gauge();
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = "";

        vm.prank(account);
        accountant.claim(accountGauges, harvestData);
    }

    function withdraw(RewardVault rewardVault, address account, uint256 amount) internal {
        vm.prank(account);
        rewardVault.withdraw(amount, account, account);
    }

    function transferShares(RewardVault rewardVault, address from, address to, uint256 amount) internal {
        vm.prank(from);
        rewardVault.transfer(to, amount);
    }

    //////////////////////////////////////////////////////
    /// --- VALIDATION HELPERS
    //////////////////////////////////////////////////////

    /// TODO: Implement this.
    function assertDeploymentValid(RewardVault[] memory vaults, RewardReceiver[] memory receivers) internal pure {
        RewardVault vault;
        RewardReceiver receiver;
        for (uint256 i = 0; i < vaults.length; i++) {
            vault = vaults[i];
            receiver = receivers[i];
        }
    }

    //////////////////////////////////////////////////////
    /// --- FUZZING HELPERS
    //////////////////////////////////////////////////////

    function _generateAccountPositionsAndRewards() internal returns (AccountPosition[] memory, uint256[] memory) {
        uint256 length = bound(uint256(keccak256(abi.encode("length"))), 1, MAX_ACCOUNT_POSITIONS);

        uint256[] memory rewards = new uint256[](length);
        AccountPosition[] memory positions = new AccountPosition[](length);

        for (uint256 i = 0; i < length; i++) {
            address gauge = gauges[i % gauges.length];
            uint256 maxAmount = IERC20(gauge).totalSupply();

            uint256 baseAmount = bound(uint256(keccak256(abi.encode("baseAmount", i))), 1e18, maxAmount);
            uint256 additionalAmount = bound(uint256(keccak256(abi.encode("additionalAmount", i))), 1e18, baseAmount);
            uint256 partialWithdrawAmount =
                bound(uint256(keccak256(abi.encode("partialWithdrawAmount", i))), 1e18, baseAmount);

            positions[i] = AccountPosition({
                account: makeAddr(string(abi.encodePacked("Account", i))),
                baseAmount: baseAmount,
                additionalAmount: additionalAmount,
                partialWithdrawAmount: partialWithdrawAmount,
                gaugeIndex: i % gauges.length,
                transferReceiver: makeAddr(string(abi.encodePacked("TransferReceiver", i)))
            });

            rewards[i] = bound(uint256(keccak256(abi.encode("rewards", i))), 1e18, MAX_REWARDS);
        }

        return (positions, rewards);
    }
}
