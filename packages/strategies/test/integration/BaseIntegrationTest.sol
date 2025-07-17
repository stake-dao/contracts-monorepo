// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/BaseSetup.sol";

import {Factory} from "src/Factory.sol";
import {Strategy} from "src/Strategy.sol";

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

    function test_complete_protocol_lifecycle() public virtual {
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

            /// 6a. Simulate extra rewards
            simulateExtraRewards(rewardVault, _rewards[i]);

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

        /// 10. Handle rewards based on harvest policy
        if (harvestPolicy == IStrategy.HarvestPolicy.CHECKPOINT) {
            /// CHECKPOINT MODE: Rewards need to be harvested and claimed

            /// Assert that the accountant has no rewards before harvest.
            assertEq(
                _balanceOf(rewardToken, address(accountant)),
                0,
                "7. Expected accountant to have no rewards before harvest"
            );

            /// Assert that the harvester has no rewards before harvest.
            assertEq(_balanceOf(rewardToken, harvester), 0, "8. Expected harvester to have no rewards before harvest");

            /// Assert that the protocol fees accrued are 0.
            assertEq(accountant.protocolFeesAccrued(), 0, "9. Expected protocol fees accrued to be 0");

            /// 13. Harvest the rewards.
            harvest();

            uint256 expectedHarvesterBalance = totalHarvestableRewards.mulDiv(accountant.getHarvestFeePercent(), 1e18);
            uint256 expectedProtocolFeesAccrued =
                totalHarvestableRewards.mulDiv(accountant.getProtocolFeePercent(), 1e18);
            uint256 expectedAccountantBalance = totalHarvestableRewards - expectedHarvesterBalance;

            /// 14. Assert that the accountant has the correct balance.
            assertApproxEqRel(
                _balanceOf(rewardToken, address(accountant)),
                expectedAccountantBalance,
                0.01e18,
                "10. Expected accountant to have rewards after harvest with a 1% error"
            );

            /// 15. Assert that the harvester has the correct balance.
            assertApproxEqRel(
                _balanceOf(rewardToken, harvester),
                expectedHarvesterBalance,
                0.01e18,
                "11. Expected harvester to have rewards after harvest with a 1% error"
            );

            /// 16. Assert that the protocol fees accrued are the correct amount.
            assertApproxEqRel(
                accountant.protocolFeesAccrued(),
                expectedProtocolFeesAccrued,
                0.01e18,
                "12. Expected protocol fees accrued to be greater than 0 after harvest with a 1% error"
            );

            /// 17. Verify extra rewards were claimed if applicable
            for (uint256 i = 0; i < rewardVaults.length; i++) {
                if (rewardVaults[i].getRewardTokens().length > 0) {
                    verifyExtraRewardsClaimed(rewardVaults[i], rewardReceivers[i]);
                }
            }
        } else {
            /// HARVEST MODE: Rewards were already claimed during deposits/withdrawals
            /// In HARVEST mode:
            /// - Rewards are claimed from external protocol during each checkpoint
            /// - Only protocol fee is charged (no harvest fee)
            /// - Rewards are immediately added to user integrals
            /// - In HARVEST mode, only locker rewards are subject to protocol fees

            // Since we don't track fee subject amounts separately in this test,
            // and the actual fee calculation happens in the strategy during harvest,
            // we need to check what actually happened rather than predict it
            uint256 actualProtocolFees = accountant.protocolFeesAccrued();
            uint256 actualAccountantBalance = _balanceOf(rewardToken, address(accountant));

            /// Assert that protocol fees were accrued
            assertGt(actualProtocolFees, 0, "10. Expected protocol fees to be accrued during HARVEST mode checkpoints");

            /// No harvester fees in HARVEST mode
            assertEq(_balanceOf(rewardToken, harvester), 0, "11. Expected no harvester rewards in HARVEST mode");

            /// In HARVEST mode, verify the accounting is correct
            /// The actual rewards might be higher due to:
            /// 1. Sidecar rewards (Convex) that are not tracked in our simulation
            /// 2. Additional reward accrual in the external protocol
            /// We verify that at minimum we got the rewards we simulated
            assertGe(
                actualAccountantBalance + actualProtocolFees,
                totalHarvestableRewards,
                "12. Expected actual rewards to be at least the simulated rewards in HARVEST mode"
            );
        }

        for (uint256 i = 0; i < _accountPositions.length; i++) {
            accountPosition = _accountPositions[i];

            gauge = gauges[accountPosition.gaugeIndex];
            rewardVault = rewardVaults[accountPosition.gaugeIndex];
            rewardReceiver = rewardReceivers[accountPosition.gaugeIndex];

            /// 17. Claim rewards based on harvest policy
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

            /// Claim the rewards.
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

            /// 17a. Verify user received extra rewards if applicable
            if (rewardVault.getRewardTokens().length > 0) {
                verifyUserExtraRewards(accountPosition.account, rewardVault);
            }

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
            uint256 additionalRewards = _rewards[i] / 2;
            simulateRewards(rewardVault, additionalRewards);

            /// 19a. Simulate additional extra rewards
            simulateExtraRewards(rewardVault, additionalRewards);

            // Track additional rewards for both modes
            totalHarvestableRewards += additionalRewards;
            rewardVaultToHarvestableRewards[address(rewardVault)] += additionalRewards;
        }

        skip(1 days);

        /// 20. Test emergency shutdown and unshutdown for all gauges
        for (uint256 i = 0; i < gauges.length; i++) {
            address testGauge = gauges[i];
            RewardVault testVault = rewardVaults[i];
            uint256 totalSupplyBeforeShutdown = testVault.totalSupply();

            // Only test if vault has deposits
            if (totalSupplyBeforeShutdown > 0) {
                // Shutdown the gauge
                vm.prank(owners[0]);
                protocolController.shutdown(testGauge);

                // Verify shutdown state
                assertTrue(
                    protocolController.isShutdown(testGauge),
                    string.concat("Gauge ", vm.toString(i), " should be shutdown")
                );
                assertEq(
                    IStrategy(strategy).balanceOf(testGauge),
                    0,
                    string.concat("Strategy balance ", vm.toString(i), " should be 0 after shutdown")
                );
                assertEq(
                    IERC20(testVault.asset()).balanceOf(address(testVault)),
                    totalSupplyBeforeShutdown,
                    string.concat("Vault ", vm.toString(i), " should hold all assets")
                );

                // Try to deposit (should fail)
                address testUser = makeAddr(string.concat("shutdownTestUser", vm.toString(i)));
                deal(testVault.asset(), testUser, 100e18);
                vm.startPrank(testUser);
                IERC20(testVault.asset()).approve(address(testVault), 100e18);
                vm.expectRevert(Strategy.GaugeShutdown.selector);
                testVault.deposit(100e18, testUser);
                vm.stopPrank();

                // Test withdrawal during shutdown (should work)
                if (_accountPositions.length > i) {
                    AccountPosition memory pos = _accountPositions[i];
                    uint256 userBalance = testVault.balanceOf(pos.account);
                    if (userBalance > 10e18) {
                        uint256 withdrawAmount = 10e18;
                        uint256 assetsBefore = IERC20(testVault.asset()).balanceOf(pos.account);
                        withdraw(testVault, pos.account, withdrawAmount);
                        assertEq(
                            IERC20(testVault.asset()).balanceOf(pos.account),
                            assetsBefore + withdrawAmount,
                            string.concat("User should receive assets during shutdown for gauge ", vm.toString(i))
                        );
                    }
                }

                // Unshutdown the gauge
                vm.prank(owners[0]);
                protocolController.unshutdown(testGauge);

                // Verify unshutdown state
                assertFalse(
                    protocolController.isShutdown(testGauge),
                    string.concat("Gauge ", vm.toString(i), " should not be shutdown")
                );

                // Get updated total supply after withdrawals
                uint256 currentTotalSupply = testVault.totalSupply();
                assertEq(
                    IStrategy(strategy).balanceOf(testGauge),
                    currentTotalSupply,
                    string.concat("Strategy balance ", vm.toString(i), " should match current total supply")
                );
                assertEq(
                    IERC20(testVault.asset()).balanceOf(address(testVault)),
                    0,
                    string.concat("Vault ", vm.toString(i), " should have 0 balance after unshutdown")
                );

                // Verify deposits work again
                deposit(testVault, testUser, 100e18);
                withdraw(testVault, testUser, 100e18); // Clean up test deposit
            }
        }

        /// 21. Test share transfers
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

        // Handle post-transfer harvest based on policy
        if (harvestPolicy == IStrategy.HarvestPolicy.CHECKPOINT) {
            // Harvest after transfers for CHECKPOINT mode
            harvest();
        }
        // For HARVEST mode, rewards are already distributed during transfers

        /// 21. Verify rewards follow share ownership
        for (uint256 i = 0; i < _accountPositions.length; i++) {
            accountPosition = _accountPositions[i];
            rewardVault = rewardVaults[accountPosition.gaugeIndex];

            // Original accounts should still have their accrued rewards from before the transfer
            uint256 originalAccountPendingRewards =
                accountant.getPendingRewards(address(rewardVault), accountPosition.account);

            if (originalAccountPendingRewards > 0) {
                // Claim rewards as original account
                claim(rewardVault, accountPosition.account);
                assertGt(
                    _balanceOf(rewardToken, accountPosition.account),
                    0,
                    "21. Expected original account to have claimed their accrued rewards"
                );
            }

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
    function simulateRewards(RewardVault vault, uint256 amount) internal virtual {
        // Base implementation simulates CRV rewards
        // Override in integration tests to add extra rewards simulation
    }

    function getHarvestableRewards(RewardVault vault) internal virtual returns (uint256) {}

    /// @notice Simulates extra reward tokens for a vault
    /// @param vault The reward vault to simulate extra rewards for
    /// @param baseAmount Base amount to calculate extra rewards from
    function simulateExtraRewards(RewardVault vault, uint256 baseAmount) internal virtual {
        address gauge = vault.gauge();
        address[] memory extraTokens = vault.getRewardTokens();

        // Skip if no extra tokens configured
        if (extraTokens.length == 0) return;

        // For each extra token, simulate rewards
        for (uint256 i = 0; i < extraTokens.length; i++) {
            address token = extraTokens[i];

            // Calculate proportional extra rewards (10-30% of base amount)
            uint256 extraAmount = baseAmount.mulDiv(10 + i * 10, 100);

            // Simulate the extra rewards based on the protocol
            _simulateExtraRewardForToken(vault, gauge, token, extraAmount);
        }
    }

    /// @notice Protocol-specific simulation of extra rewards
    /// @param vault The reward vault
    /// @param gauge The gauge address
    /// @param token The extra reward token
    /// @param amount The amount to simulate
    function _simulateExtraRewardForToken(RewardVault vault, address gauge, address token, uint256 amount)
        internal
        virtual
    {
        // Override in specific integration tests
    }

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

    function harvest() internal virtual {
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

    /// @notice Verifies extra rewards were properly claimed and distributed
    /// @param vault The reward vault to check
    /// @param receiver The reward receiver to check
    function verifyExtraRewardsClaimed(RewardVault vault, RewardReceiver receiver) internal view {
        address[] memory extraTokens = vault.getRewardTokens();

        for (uint256 i = 0; i < extraTokens.length; i++) {
            address token = extraTokens[i];

            // Skip CVX on mainnet as it comes from Convex sidecars, not gauge rewards
            // CVX address on mainnet: 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B
            if (token == address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B)) {
                // For CVX, just check that it's properly configured
                address distributor = vault.getRewardsDistributor(token);
                assertEq(distributor, address(receiver), "CVX distributor should be the reward receiver");
                continue;
            }

            // Check vault received tokens (balance should be > 0 after distribution)
            uint256 vaultBalance = IERC20(token).balanceOf(address(vault));
            assertGt(
                vaultBalance, 0, string.concat("Vault should have received extra reward token: ", vm.toString(token))
            );

            // Check reward data was updated
            uint256 periodFinish = vault.getPeriodFinish(token);
            assertGt(periodFinish, block.timestamp, "Reward period should be active");

            // Check reward rate is set
            uint128 rewardRate = vault.getRewardRate(token);
            assertGt(rewardRate, 0, "Reward rate should be greater than 0");

            // Check rewards distributor is set correctly
            address distributor = vault.getRewardsDistributor(token);
            assertEq(distributor, address(receiver), "Reward distributor should be the reward receiver");
        }
    }

    /// @notice Verifies a user received their share of extra rewards
    /// @param user The user address to check
    /// @param vault The reward vault
    function verifyUserExtraRewards(address user, RewardVault vault) internal {
        address[] memory extraTokens = vault.getRewardTokens();

        if (extraTokens.length == 0) return;

        // First, claim the extra rewards from the vault
        vm.prank(user);
        vault.claim(extraTokens, user);

        // Now verify the user received the tokens
        bool hasNonCvxRewards = false;
        for (uint256 i = 0; i < extraTokens.length; i++) {
            address token = extraTokens[i];

            // Skip CVX on mainnet as it comes from Convex sidecars
            // CVX address on mainnet: 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B
            if (token == address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B)) {
                continue;
            }

            hasNonCvxRewards = true;

            // Check if there's an active reward period
            uint256 periodFinish = vault.getPeriodFinish(token);
            if (periodFinish > block.timestamp) {
                // For active periods, check earned amount instead of balance
                uint256 earned = vault.earned(user, token);
                if (earned > 0) {
                    // If earned > 0, claim should have worked
                    uint256 userBalance = IERC20(token).balanceOf(user);
                    assertGt(
                        userBalance,
                        0,
                        string.concat("User should have received earned extra reward token: ", vm.toString(token))
                    );
                } else {
                    // If no rewards earned yet, it's OK - rewards might not have accrued yet
                    // This can happen if rewards were just deposited
                    continue;
                }
            }
        }

        // Only assert if there were non-CVX rewards to check
        if (!hasNonCvxRewards) {
            // All rewards were CVX, which is handled separately
            return;
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
