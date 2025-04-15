// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/src/console.sol";

import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {CurveAllocator} from "src/integrations/curve/CurveAllocator.sol";
import {IBalanceProvider} from "src/interfaces/IBalanceProvider.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {RewardVault} from "src/RewardVault.sol";
import {BaseCurveTest} from "test/integration/curve/BaseCurveTest.sol";

abstract contract CurveIntegrationTest is BaseCurveTest {
    constructor(uint256 _pid1, uint256 _pid2) BaseCurveTest(_pid1) {
        pid2 = _pid2;
    }

    /// @notice The WBTC address
    /// @dev Used to test small decimal rewards
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    /// @notice The Curve Admin address
    address public constant CURVE_ADMIN = 0x40907540d8a6C65c637785e8f8B742ae6b0b9968;

    // Replace single account with multiple accounts
    uint256 public constant NUM_ACCOUNTS = 3;
    address[] public accounts;
    address public harvester = makeAddr("Harvester");

    // Second PID and gauge variables
    uint256 public pid2;
    address public lpToken2;
    uint256 public totalSupply2;
    ILiquidityGauge public gauge2;

    // Vault contract instances for both PIDs
    CurveAllocator public curveAllocator;

    RewardVault public rewardVault2;
    RewardReceiver public rewardReceiver2;
    ConvexSidecar public convexSidecar2;

    function setUp() public virtual override {
        super.setUp();

        // Initialize multiple accounts
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            accounts.push(makeAddr(string(abi.encodePacked("Account", i))));
        }

        // Setup second gauge from pid2
        (address _lpToken2,, address _gauge2,,,) = BOOSTER.poolInfo(pid2);
        lpToken2 = _lpToken2;
        gauge2 = ILiquidityGauge(_gauge2);
        totalSupply2 = IBalanceProvider(lpToken2).totalSupply();

        // Initialize the second gauge using the helper function
        _setupGauge(address(gauge2));

        /// 0. Deploy the allocator contract.
        curveAllocator = new CurveAllocator(address(locker), address(gateway), address(convexSidecarFactory));

        /// 1. Set the allocator.
        protocolController.setAllocator(protocolId, address(curveAllocator));

        /// 2. Deploy the first Reward Vault contract through the factory.
        (address _rewardVault, address _rewardReceiver, address _sidecar) = curveFactory.create(pid);

        rewardVault = RewardVault(_rewardVault);
        rewardReceiver = RewardReceiver(_rewardReceiver);
        convexSidecar = ConvexSidecar(_sidecar);

        /// 3. Deploy the second Reward Vault contract through the factory.
        (address _rewardVault2, address _rewardReceiver2, address _sidecar2) = curveFactory.create(pid2);

        rewardVault2 = RewardVault(_rewardVault2);
        rewardReceiver2 = RewardReceiver(_rewardReceiver2);
        convexSidecar2 = ConvexSidecar(_sidecar2);

        /// 4. Set up the accounts with LP tokens and approvals for both gauges
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // First gauge LP tokens
            deal(lpToken, accounts[i], totalSupply / NUM_ACCOUNTS);
            vm.prank(accounts[i]);
            IERC20(lpToken).approve(address(rewardVault), totalSupply / NUM_ACCOUNTS);

            // Second gauge LP tokens
            deal(lpToken2, accounts[i], totalSupply2 / NUM_ACCOUNTS);
            vm.prank(accounts[i]);
            IERC20(lpToken2).approve(address(rewardVault2), totalSupply2 / NUM_ACCOUNTS);
        }

        /// Add WBTC as Extra Rewards on Gauge
        vm.prank(CURVE_ADMIN);
        gauge.add_reward(WBTC, address(this));

        /// Add WBTC as Extra Rewards on Gauge 2
        vm.prank(CURVE_ADMIN);
        gauge2.add_reward(WBTC, address(this));

        /// Mock the reward data to be active in order for syncRewardTokens to work.
        vm.mockCall(
            address(gauge),
            abi.encodeWithSelector(gauge.reward_data.selector),
            abi.encode(WBTC, address(this), block.timestamp + 1 days, 0, block.timestamp, 0)
        );
        vm.mockCall(
            address(gauge2),
            abi.encodeWithSelector(gauge2.reward_data.selector),
            abi.encode(WBTC, address(this), block.timestamp + 1 days, 0, block.timestamp, 0)
        );

        /// Sync the reward tokens on the gauges
        curveFactory.syncRewardTokens(address(gauge));
        curveFactory.syncRewardTokens(address(gauge2));
    }

    // Define a struct to store test parameters to avoid stack too deep errors
    struct TestParams {
        uint256 baseAmount;
        uint256 totalDeposited;
        uint256[] depositAmounts;
        uint256[] remainingShares;
        uint256 totalExpectedRewards;
        uint256 totalClaimedRewards;
        uint256 totalWithdrawn;
        uint256 expectedRewards1;
        uint256 expectedRewards2;
        uint256 expectedRewards3;
        uint256 harvestRewards;
        uint256 accountantRewards;
        uint256 harvestRewards2;
        uint256 totalClaimedRewards2;
        uint256 accountantRewards2;
        uint256 totalCVXClaimed;
        // Second gauge params
        uint256 baseAmount2;
        uint256 totalDeposited2;
        uint256[] depositAmounts2;
        uint256[] remainingShares2;
        uint256 totalExpectedRewards2nd;
        uint256 totalClaimedRewards2nd;
        uint256 totalWithdrawn2;
        uint256 expectedRewards1_2nd;
        uint256 expectedRewards2_2nd;
        uint256 expectedRewards3_2nd;
        address transferReceiver;
    }

    function test_deposit_withdraw_sequentially(uint256 _baseAmount, uint256 _baseAmount2) public {
        // 1. Set up test parameters with fuzzing
        vm.assume(_baseAmount > 1e18);
        vm.assume(_baseAmount < (totalSupply / NUM_ACCOUNTS) / 10); // Ensure reasonable amounts

        vm.assume(_baseAmount2 > 1e18);
        vm.assume(_baseAmount2 < (totalSupply2 / NUM_ACCOUNTS) / 10);

        // 2. Initialize the test parameters struct
        TestParams memory params;
        params.transferReceiver = makeAddr("Transfer Receiver");
        params.baseAmount = _baseAmount;
        params.baseAmount2 = _baseAmount2;
        params.depositAmounts = new uint256[](NUM_ACCOUNTS);
        params.depositAmounts2 = new uint256[](NUM_ACCOUNTS);
        params.remainingShares = new uint256[](NUM_ACCOUNTS);
        params.remainingShares2 = new uint256[](NUM_ACCOUNTS);

        // Phase 1: Handle Deposits
        _handleDeposits(params);

        // Verify deposits
        assertEq(
            curveStrategy.balanceOf(address(gauge)),
            params.totalDeposited,
            "Initial deposit amount mismatch for gauge 1"
        );
        assertEq(
            curveStrategy.balanceOf(address(gauge2)),
            params.totalDeposited2,
            "Initial deposit amount mismatch for gauge 2"
        );

        // Phase 2: Handle First Round Rewards
        _handleFirstRewards(params);

        // Phase 3: Handle Additional Deposits
        _handleAdditionalDeposits(params);

        // Verify total deposits
        assertEq(
            curveStrategy.balanceOf(address(gauge)), params.totalDeposited, "Second deposit amount mismatch for gauge 1"
        );
        assertEq(
            curveStrategy.balanceOf(address(gauge2)),
            params.totalDeposited2,
            "Second deposit amount mismatch for gauge 2"
        );

        // Phase 4: Handle First Harvest and Claims
        address[] memory gauges = new address[](2);
        gauges[0] = address(gauge);
        gauges[1] = address(gauge2);
        bytes[] memory harvestData = new bytes[](2);

        _handleFirstHarvestAndClaims(params, gauges, harvestData);

        // Phase 5: Handle Partial Withdrawals
        _handlePartialWithdrawals(params);

        // Verify partial withdrawals
        assertEq(
            curveStrategy.balanceOf(address(gauge)),
            params.totalDeposited - params.totalWithdrawn,
            "Strategy balance after partial withdrawal mismatch for gauge 1"
        );
        assertEq(
            curveStrategy.balanceOf(address(gauge2)),
            params.totalDeposited2 - params.totalWithdrawn2,
            "Strategy balance after partial withdrawal mismatch for gauge 2"
        );

        // Phase 6: Handle Second Harvest and Claims
        _handleSecondHarvestAndClaims(params, gauges, harvestData);

        // Phase 7: Handle CVX Rewards and Final Withdrawals
        _handleCVXRewardsAndFinalWithdrawals(params);

        // Verify final state
        assertEq(
            curveStrategy.balanceOf(address(gauge)),
            0,
            "Strategy should have only initial balance after full withdrawal for gauge 1"
        );
        assertEq(
            curveStrategy.balanceOf(address(gauge2)),
            0,
            "Strategy should have only initial balance after full withdrawal for gauge 2"
        );
    }

    /// Issue: https://github.com/stake-dao/contracts-monorepo/issues/111
    function test_netCredited_DecreasingRewards(uint256 _baseAmount, uint256 _baseAmount2) public {
        // 1. Set up test parameters with fuzzing
        vm.assume(_baseAmount > 1e18);
        vm.assume(_baseAmount < (totalSupply / NUM_ACCOUNTS) / 10); // Ensure reasonable amounts

        vm.assume(_baseAmount2 > 1e18);
        vm.assume(_baseAmount2 < (totalSupply2 / NUM_ACCOUNTS) / 10);

        // 2. Initialize the test parameters struct
        TestParams memory params;
        params.transferReceiver = makeAddr("Transfer Receiver");
        params.baseAmount = _baseAmount;
        params.baseAmount2 = _baseAmount2;
        params.depositAmounts = new uint256[](NUM_ACCOUNTS);
        params.depositAmounts2 = new uint256[](NUM_ACCOUNTS);
        params.remainingShares = new uint256[](NUM_ACCOUNTS);
        params.remainingShares2 = new uint256[](NUM_ACCOUNTS);

        // Phase 1: Handle Deposits
        _handleDeposits(params);
        // 1. First large rewards
        address vault = protocolController.vaults(address(gauge));

        // Get initial integral value
        uint256 integralBefore = accountant.getVaultIntegral(vault);

        // Generate large rewards (1000 CRV)
        uint256 largeReward = 1000e18;
        _inflateRewards(address(gauge), largeReward);

        // Skip time to simulate reward accrual
        skip(1 hours);

        // Setup harvest
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        bytes[] memory harvestData = new bytes[](1);

        // Harvest the large rewards
        vm.prank(harvester);
        accountant.harvest(gauges, harvestData, harvester);

        // Get integral after first harvest
        uint256 integralAfterFirst = accountant.getVaultIntegral(vault);

        // Verify integral increased
        assertGt(integralAfterFirst, integralBefore, "Integral should increase after first harvest");

        // 2. Now generate smaller rewards (30 CRV)
        uint256 smallReward = 30e18;
        _inflateRewards(address(gauge), smallReward);

        // Skip time to simulate reward accrual
        skip(1 hours);

        // Get integral before second harvest
        uint256 integralBeforeSecond = accountant.getVaultIntegral(vault);

        // Harvest the smaller rewards
        vm.prank(harvester);
        accountant.harvest(gauges, harvestData, harvester);

        // Get integral after second harvest
        uint256 integralAfterSecond = accountant.getVaultIntegral(vault);

        // Key check: verify integral still increases even with smaller rewards
        // With the bug, the integral would not increase for smaller rewards after a larger reward
        assertGt(
            integralAfterSecond, integralBeforeSecond, "Integral should still increase after harvesting smaller rewards"
        );
    }

    // Helper function to handle initial deposits for both gauges
    function _handleDeposits(TestParams memory params) internal {
        // First deposit round for first gauge
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 accountAmount = params.baseAmount * (i + 1);
            params.depositAmounts[i] = accountAmount;
            params.totalDeposited += accountAmount;

            vm.prank(accounts[i]);
            rewardVault.deposit(accountAmount, accounts[i]);
        }

        // First deposit round for second gauge
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 accountAmount = params.baseAmount2 * (i + 1);
            params.depositAmounts2[i] = accountAmount;
            params.totalDeposited2 += accountAmount;

            vm.prank(accounts[i]);
            rewardVault2.deposit(accountAmount, accounts[i]);
        }
    }

    // Helper function to handle the first rewards round
    function _handleFirstRewards(TestParams memory params) internal {
        // First inflation of rewards
        params.expectedRewards1 = _inflateRewards(address(gauge), 1000e18);
        params.expectedRewards1_2nd = _inflateRewards(address(gauge2), 1500e18);

        // Skip time to simulate reward accrual
        skip(1 hours);

        // Check for rewards in the Convex Sidecars
        uint256 sidecarRewards = convexSidecar.getPendingRewards();
        uint256 sidecarRewards2 = convexSidecar2.getPendingRewards();

        params.totalExpectedRewards += params.expectedRewards1 + sidecarRewards;
        params.totalExpectedRewards2nd += params.expectedRewards1_2nd + sidecarRewards2;
    }

    // Helper function to handle additional deposits
    function _handleAdditionalDeposits(TestParams memory params) internal {
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // For first gauge - add half the previous amount
            uint256 accountAmount = params.baseAmount * (i + 1) / 2;
            params.depositAmounts[i] += accountAmount;
            params.totalDeposited += accountAmount;

            deal(lpToken, accounts[i], accountAmount);
            vm.prank(accounts[i]);
            IERC20(lpToken).approve(address(rewardVault), accountAmount);
            vm.prank(accounts[i]);
            rewardVault.deposit(accountAmount, accounts[i]);

            // For second gauge - add half the previous amount
            uint256 accountAmount2 = params.baseAmount2 * (i + 1) / 2;
            params.depositAmounts2[i] += accountAmount2;
            params.totalDeposited2 += accountAmount2;

            deal(lpToken2, accounts[i], accountAmount2);
            vm.prank(accounts[i]);
            IERC20(lpToken2).approve(address(rewardVault2), accountAmount2);
            vm.prank(accounts[i]);
            rewardVault2.deposit(accountAmount2, accounts[i]);
        }

        // Second inflation of rewards
        params.expectedRewards2 = _inflateRewards(address(gauge), 1200e18);
        params.expectedRewards2_2nd = _inflateRewards(address(gauge2), 1800e18);

        // Skip time
        skip(1 hours);

        // Check Sidecar rewards
        uint256 sidecarRewards = convexSidecar.getPendingRewards();
        uint256 sidecarRewards2 = convexSidecar2.getPendingRewards();

        // Total rewards are from both Curve and Convex
        params.totalExpectedRewards = params.expectedRewards2 + sidecarRewards;
        params.totalExpectedRewards2nd = params.expectedRewards2_2nd + sidecarRewards2;
    }

    // Helper function to handle first harvest and claims
    function _handleFirstHarvestAndClaims(TestParams memory params, address[] memory gauges, bytes[] memory harvestData)
        internal
    {
        // Harvest rewards from both gauges
        vm.prank(harvester);
        accountant.harvest(gauges, harvestData, harvester);

        harvestData = new bytes[](0);

        // Track harvester rewards
        params.harvestRewards = _balanceOf(rewardToken, harvester);

        // Each account claims rewards
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 beforeClaim = _balanceOf(rewardToken, accounts[i]);

            vm.prank(accounts[i]);
            accountant.claim(gauges, harvestData);

            uint256 afterClaim = _balanceOf(rewardToken, accounts[i]);
            uint256 claimed = afterClaim - beforeClaim;

            params.totalClaimedRewards += claimed;

            // Verify rewards received
            assertGt(claimed, 0, "Account should receive rewards");
        }

        // Track accountant rewards
        params.accountantRewards = _balanceOf(rewardToken, address(accountant));

        // Verify reward distribution
        uint256 actualTotalDistributed = params.harvestRewards + params.totalClaimedRewards + params.accountantRewards;
        uint256 totalExpectedFromBothGauges = params.totalExpectedRewards + params.totalExpectedRewards2nd;

        assertApproxEqRel(
            actualTotalDistributed,
            totalExpectedFromBothGauges,
            0.01e18, // Tolerance for rounding
            "Total rewards mismatch from both gauges"
        );
    }

    // Helper function to handle partial withdrawals
    function _handlePartialWithdrawals(TestParams memory params) internal {
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // First gauge withdrawals
            uint256 withdrawAmount = params.depositAmounts[i] / 2;
            params.totalWithdrawn += withdrawAmount;

            uint256 beforeWithdraw = _balanceOf(lpToken, accounts[i]);

            vm.prank(accounts[i]);
            rewardVault.withdraw(withdrawAmount, accounts[i], accounts[i]);

            uint256 afterWithdraw = _balanceOf(lpToken, accounts[i]);
            params.remainingShares[i] = rewardVault.balanceOf(accounts[i]);

            // Verify LP tokens returned correctly
            assertEq(afterWithdraw - beforeWithdraw, withdrawAmount, "Partial withdrawal amount mismatch for gauge 1");

            // Second gauge withdrawals
            uint256 withdrawAmount2 = params.depositAmounts2[i] / 2;
            params.totalWithdrawn2 += withdrawAmount2;

            uint256 beforeWithdraw2 = _balanceOf(lpToken2, accounts[i]);

            vm.prank(accounts[i]);
            rewardVault2.withdraw(withdrawAmount2, accounts[i], accounts[i]);

            uint256 afterWithdraw2 = _balanceOf(lpToken2, accounts[i]);
            params.remainingShares2[i] = rewardVault2.balanceOf(accounts[i]);

            // Verify LP tokens returned correctly
            assertEq(
                afterWithdraw2 - beforeWithdraw2, withdrawAmount2, "Partial withdrawal amount mismatch for gauge 2"
            );
        }
    }

    // Helper function to handle second harvest and claims
    function _handleSecondHarvestAndClaims(
        TestParams memory params,
        address[] memory gauges,
        bytes[] memory harvestData
    ) internal {
        // Third inflation of rewards
        params.expectedRewards3 = _inflateRewards(address(gauge), 1500e18);
        params.expectedRewards3_2nd = _inflateRewards(address(gauge2), 2000e18);

        skip(1 hours);

        // Check Sidecar rewards
        uint256 sidecarRewards = convexSidecar.getPendingRewards();
        uint256 sidecarRewards2 = convexSidecar2.getPendingRewards();

        // New rewards after harvest
        uint256 newRewards = params.expectedRewards3 + sidecarRewards;
        uint256 newRewards2 = params.expectedRewards3_2nd + sidecarRewards2;
        uint256 totalNewRewards = newRewards + newRewards2;

        /// Before Harvesting, transfer shares to make sure we didn't miss any rewards
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            vm.prank(accounts[i]);
            rewardVault.transfer(params.transferReceiver, params.remainingShares[i]);

            vm.prank(accounts[i]);
            rewardVault2.transfer(params.transferReceiver, params.remainingShares2[i]);
        }

        // Harvest again
        vm.prank(harvester);
        accountant.harvest(gauges, harvestData, harvester);

        // Track harvester rewards for second round
        params.harvestRewards2 = _balanceOf(rewardToken, harvester) - params.harvestRewards;

        uint256 totalClaimedRewards2 = 0;

        // Clear harvest data
        harvestData = new bytes[](0);

        // Each account claims rewards again
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 beforeClaim = _balanceOf(rewardToken, accounts[i]);

            vm.prank(accounts[i]);
            accountant.claim(gauges, harvestData);

            uint256 afterClaim = _balanceOf(rewardToken, accounts[i]);
            uint256 claimed = afterClaim - beforeClaim;

            totalClaimedRewards2 += claimed;

            /// Transfer the shares back to the account
            vm.prank(params.transferReceiver);
            rewardVault.transfer(accounts[i], params.remainingShares[i]);

            vm.prank(params.transferReceiver);
            rewardVault2.transfer(accounts[i], params.remainingShares2[i]);
        }

        params.totalClaimedRewards2 = totalClaimedRewards2;

        // Track remaining rewards in accountant
        params.accountantRewards2 = _balanceOf(rewardToken, address(accountant)) - params.accountantRewards;

        // Verify second distribution
        uint256 actualTotalDistributed2 =
            params.harvestRewards2 + params.totalClaimedRewards2 + params.accountantRewards2;

        assertApproxEqRel(
            actualTotalDistributed2, totalNewRewards, 0.01e18, "Second round rewards mismatch for both gauges"
        );
    }

    // Helper function to handle CVX rewards and final withdrawals
    function _handleCVXRewardsAndFinalWithdrawals(TestParams memory params) internal {
        // Add CVX rewards to test extra rewards distribution
        uint256 totalWBTC = 1e18;
        uint256 totalCVX = 1_000_000e18;
        deal(CVX, address(rewardReceiver), totalCVX / 2);
        deal(CVX, address(rewardReceiver2), totalCVX / 2);

        deal(WBTC, address(rewardReceiver), totalWBTC / 2);
        deal(WBTC, address(rewardReceiver2), totalWBTC / 2);

        // Claim and distribute extra rewards from both sidecars
        convexSidecar.claimExtraRewards();
        rewardReceiver.distributeRewards();

        convexSidecar2.claimExtraRewards();
        rewardReceiver2.distributeRewards();

        // Wait for rewards to vest
        skip(1 weeks);

        // Complete withdrawals
        _finalizeWithdrawals(
            params.remainingShares, params.remainingShares2, params.depositAmounts, params.depositAmounts2
        );

        // Process CVX claims
        address[] memory rewardTokens = rewardVault.getRewardTokens();
        address[] memory rewardTokens2 = rewardVault2.getRewardTokens();
        _processExtraRewards(rewardTokens, rewardTokens2, totalCVX, totalWBTC);
    }

    // Helper function to process final withdrawals for both gauges
    function _finalizeWithdrawals(
        uint256[] memory remainingShares,
        uint256[] memory remainingShares2,
        uint256[] memory depositAmounts,
        uint256[] memory depositAmounts2
    ) internal {
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // First gauge withdrawals
            uint256 remainingAmount = remainingShares[i];
            uint256 beforeWithdraw = _balanceOf(lpToken, accounts[i]);

            vm.prank(accounts[i]);
            rewardVault.withdraw(remainingAmount, accounts[i], accounts[i]);

            uint256 afterWithdraw = _balanceOf(lpToken, accounts[i]);

            // Verify all LP tokens returned
            assertEq(afterWithdraw - beforeWithdraw, remainingAmount, "Final withdrawal amount mismatch for gauge 1");

            // Verify total received matches total deposited
            assertEq(
                afterWithdraw, depositAmounts[i], "Total LP tokens returned should match total deposited for gauge 1"
            );

            // Second gauge withdrawals
            uint256 remainingAmount2 = remainingShares2[i];
            uint256 beforeWithdraw2 = _balanceOf(lpToken2, accounts[i]);

            vm.prank(accounts[i]);
            rewardVault2.withdraw(remainingAmount2, accounts[i], accounts[i]);

            uint256 afterWithdraw2 = _balanceOf(lpToken2, accounts[i]);

            // Verify all LP tokens returned
            assertEq(afterWithdraw2 - beforeWithdraw2, remainingAmount2, "Final withdrawal amount mismatch for gauge 2");

            // Verify total received matches total deposited
            assertEq(
                afterWithdraw2, depositAmounts2[i], "Total LP tokens returned should match total deposited for gauge 2"
            );
        }
    }

    // Helper function to process CVX claims and verify distribution for both gauges
    function _processExtraRewards(
        address[] memory rewardTokens,
        address[] memory rewardTokens2,
        uint256 totalCVX,
        uint256 totalWBTC
    ) internal {
        uint256 totalCVXClaimed = 0;
        uint256 totalWBTCClaimed = 0;

        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 beforeClaim = _balanceOf(CVX, accounts[i]);
            uint256 beforeClaimWBTC = _balanceOf(WBTC, accounts[i]);

            // Claim from first gauge
            vm.prank(accounts[i]);
            rewardVault.claim(rewardTokens, accounts[i]);

            // Claim from second gauge
            vm.prank(accounts[i]);
            rewardVault2.claim(rewardTokens2, accounts[i]);

            uint256 afterClaim = _balanceOf(CVX, accounts[i]);
            uint256 claimed = afterClaim - beforeClaim;

            uint256 afterClaimWBTC = _balanceOf(WBTC, accounts[i]);
            uint256 claimedWBTC = afterClaimWBTC - beforeClaimWBTC;

            totalCVXClaimed += claimed;
            totalWBTCClaimed += claimedWBTC;

            // Verify CVX rewards received
            assertGt(claimed, 0, "Account should receive CVX rewards from both gauges");
            assertGt(claimedWBTC, 0, "Account should receive WBTC rewards from both gauges");

            // Verify the claimable amount is updated for CVX
            assertEq(rewardVault.getClaimable(rewardTokens[0], accounts[i]), 0);
            assertEq(rewardVault2.getClaimable(rewardTokens2[0], accounts[i]), 0);

            // Verify the claimable amount is updated for WBTC
            assertEq(rewardVault.getClaimable(rewardTokens[1], accounts[i]), 0);
            assertEq(rewardVault2.getClaimable(rewardTokens2[1], accounts[i]), 0);
        }

        // Verify all CVX rewards were distributed
        assertApproxEqRel(
            totalCVXClaimed,
            totalCVX,
            0.05e18, // Tolerance to account for rounding and potential implementation differences
            "Total CVX claimed should match total distributed from both gauges"
        );

        // Verify all WBTC rewards were distributed
        assertApproxEqRel(
            totalWBTCClaimed,
            totalWBTC,
            0.05e18, // Tolerance to account for rounding and potential implementation differences
            "Total WBTC claimed should match total distributed from both gauges"
        );
    }
}
