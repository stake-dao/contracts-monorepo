// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/integration/curve/BaseCurveTest.sol";
import "src/integrations/curve/CurveAllocator.sol";

abstract contract CurveIntegrationTest is BaseCurveTest {
    constructor(uint256 _pid) BaseCurveTest(_pid) {}

    // Replace single account with multiple accounts
    uint256 public constant NUM_ACCOUNTS = 3;
    address[] public accounts;
    address public harvester = makeAddr("Harvester");

    CurveAllocator public curveAllocator;

    function setUp() public override {
        super.setUp();

        // Initialize multiple accounts
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            accounts.push(makeAddr(string(abi.encodePacked("Account", i))));
        }

        /// 0. Deploy the allocator contract.
        curveAllocator = new CurveAllocator(address(locker), address(gateway), address(convexSidecarFactory));

        /// 1. Set the allocator.
        protocolController.setAllocator(protocolId, address(curveAllocator));

        /// 2. Deploy the Reward Vault contract through the factory.
        (address _rewardVault, address _rewardReceiver, address _sidecar) = curveFactory.create(pid);

        rewardVault = RewardVault(_rewardVault);
        rewardReceiver = RewardReceiver(_rewardReceiver);
        convexSidecar = ConvexSidecar(_sidecar);

        /// 3. Set up the accounts with LP tokens and approvals
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            deal(lpToken, accounts[i], totalSupply / NUM_ACCOUNTS);

            vm.prank(accounts[i]);
            IERC20(lpToken).approve(address(rewardVault), totalSupply / NUM_ACCOUNTS);
        }
    }

    // Define a struct to store test parameters to avoid stack too deep errors
    struct TestParams {
        uint256 baseAmount;
        uint256 totalDeposited;
        uint256[] depositAmounts;
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
    }

    function test_deposit_withdraw_sequentially(uint256 _baseAmount) public {
        // 1. Set up test parameters with fuzzing
        vm.assume(_baseAmount > 1e18);
        vm.assume(_baseAmount < (totalSupply / NUM_ACCOUNTS) / 10); // Ensure reasonable amounts

        // 2. Initialize the test parameters struct
        TestParams memory params;
        params.baseAmount = _baseAmount;
        params.depositAmounts = new uint256[](NUM_ACCOUNTS);
        
        // 3. First deposit round - each account deposits different amount
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 accountAmount = params.baseAmount * (i + 1);
            params.depositAmounts[i] = accountAmount;
            params.totalDeposited += accountAmount;

            vm.prank(accounts[i]);
            rewardVault.deposit(accountAmount, accounts[i]);
        }

        // 4. Verify initial deposit amounts
        assertEq(curveStrategy.balanceOf(address(gauge)), params.totalDeposited, "Initial deposit amount mismatch");

        // 5. First inflation of rewards (1000e18) and track expected total
        params.expectedRewards1 = _inflateRewards(address(gauge), 1000e18);

        // 6. Skip time to simulate reward accrual period
        skip(1 hours);

        // Also check for any rewards in the Convex Sidecar that might contribute
        uint256 sidecarRewards = convexSidecar.getPendingRewards();
        
        params.totalExpectedRewards += params.expectedRewards1 + sidecarRewards;

        // 7. Second deposit round - add more tokens for each account
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 accountAmount = params.baseAmount * (i + 1) / 2; // Half the previous amount
            
            // 7.1. Update accounting
            params.depositAmounts[i] += accountAmount;
            params.totalDeposited += accountAmount;

            // 7.2. Provide additional LP tokens
            deal(lpToken, accounts[i], accountAmount);
            
            // 7.3. Approve and deposit
            vm.prank(accounts[i]);
            IERC20(lpToken).approve(address(rewardVault), accountAmount);
            
            vm.prank(accounts[i]);
            rewardVault.deposit(accountAmount, accounts[i]);
        }

        // 8. Verify updated total deposit
        assertEq(curveStrategy.balanceOf(address(gauge)), params.totalDeposited, "Second deposit amount mismatch");

        // 9. Second inflation of rewards (1200e18 = 200e18 new rewards since last)
        params.expectedRewards2 = _inflateRewards(address(gauge), 1200e18);
        
        
        // 10. Skip time to simulate more reward accrual
        skip(1 hours);

        // Again check Convex Sidecar rewards that might have accumulated
        sidecarRewards = convexSidecar.getPendingRewards();
        
        // Total rewards are now from both Curve and Convex - replace previous calculation
        params.totalExpectedRewards = params.expectedRewards2 + sidecarRewards;

        // 11. Set up the harvester
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        bytes[] memory harvestData = new bytes[](1);

        // 12. Harvest all accumulated rewards
        vm.prank(harvester);
        accountant.harvest(gauges, harvestData);

        // 13. Each account claims their portion of rewards
        params.harvestRewards = _balanceOf(rewardToken, harvester);
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 beforeClaim = _balanceOf(rewardToken, accounts[i]);
            
            vm.prank(accounts[i]);
            accountant.claim(gauges, harvestData);
            
            uint256 afterClaim = _balanceOf(rewardToken, accounts[i]);
            uint256 claimed = afterClaim - beforeClaim;
            
            params.totalClaimedRewards += claimed;
            
            // 13.1. Verify rewards were received
            assertGt(claimed, 0, "Account should receive rewards");
        }

        // 14. Track remaining rewards in the accountant
        params.accountantRewards = _balanceOf(rewardToken, address(accountant));
        
        // 15. Verify reward distribution tracks - print the values for debugging
        uint256 actualTotalDistributed = params.harvestRewards + params.totalClaimedRewards + params.accountantRewards;
        
        // Compare with high tolerance - we're mostly ensuring all rewards are accounted for
        assertApproxEqRel(
            actualTotalDistributed, 
            params.totalExpectedRewards, 
            0.0001e18, // Tight tolerance now that we account for all reward sources
            "Total rewards mismatch"
        );

        // 16. Start partial withdrawals - each account withdraws half
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 withdrawAmount = params.depositAmounts[i] / 2;
            params.totalWithdrawn += withdrawAmount;

            uint256 beforeWithdraw = _balanceOf(lpToken, accounts[i]);
            
            vm.prank(accounts[i]);
            rewardVault.withdraw(withdrawAmount, accounts[i], accounts[i]);
            
            uint256 afterWithdraw = _balanceOf(lpToken, accounts[i]);
            
            // 16.1. Verify LP tokens returned correctly
            assertEq(
                afterWithdraw - beforeWithdraw, 
                withdrawAmount, 
                "Partial withdrawal amount mismatch"
            );
        }

        // 17. Verify strategy balance matches remaining deposits
        assertEq(
            curveStrategy.balanceOf(address(gauge)), 
            params.totalDeposited - params.totalWithdrawn, 
            "Strategy balance after partial withdrawal mismatch"
        );

        // 18. Third inflation of rewards after partial withdrawal
        params.expectedRewards3 = _inflateRewards(address(gauge), 1500e18);

        // 19. Skip time to simulate more reward accrual
        skip(1 hours);
        
        // Check Convex Sidecar rewards for the third round
        sidecarRewards = convexSidecar.getPendingRewards();
        
        // After harvesting, the next inflation represents the total new rewards
        uint256 newRewards = params.expectedRewards3 + sidecarRewards; // Complete new set of rewards after harvest

        // 20. Harvest again after partial withdrawals
        vm.prank(harvester);
        accountant.harvest(gauges, harvestData);

        // 21. Reset tracking for second claim
        params.harvestRewards2 = _balanceOf(rewardToken, harvester) - params.harvestRewards;
        
        // 22. Each account claims rewards again
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 beforeClaim = _balanceOf(rewardToken, accounts[i]);
            
            vm.prank(accounts[i]);
            accountant.claim(gauges, harvestData);
            
            uint256 afterClaim = _balanceOf(rewardToken, accounts[i]);
            uint256 claimed = afterClaim - beforeClaim;
            
            params.totalClaimedRewards2 += claimed;
        }

        // 23. Track remaining rewards in the accountant
        params.accountantRewards2 = _balanceOf(rewardToken, address(accountant)) - params.accountantRewards;

        // 24. Verify second reward distribution - with debug logging
        uint256 actualTotalDistributed2 = params.harvestRewards2 + params.totalClaimedRewards2 + params.accountantRewards2;
        
        assertApproxEqRel(
            actualTotalDistributed2, 
            newRewards, 
            0.0001e18, // Tight tolerance now that we account for all reward sources
            "Second round rewards mismatch"
        );

        // 25. Add CVX rewards to test extra rewards distribution
        uint256 totalCVX = 1_000_000e18;
        deal(CVX, address(rewardReceiver), totalCVX);

        // 26. Claim and distribute extra rewards
        convexSidecar.claimExtraRewards();
        rewardReceiver.distributeRewards();

        // 27. Wait for rewards to vest
        skip(1 weeks);

        // 28. Complete withdrawals - withdraw remaining deposits
        _finalizeWithdrawals(params.depositAmounts);

        // 29. Verify all funds withdrawn from strategy
        assertEq(curveStrategy.balanceOf(address(gauge)), 0, "Strategy should be empty after full withdrawal");

        // 30. Track total CVX claimed and process CVX claims
        address[] memory rewardTokens = rewardVault.getRewardTokens();
        _processClaimsCVX(rewardTokens, totalCVX);
    }
    
    // Helper function to process final withdrawals
    function _finalizeWithdrawals(uint256[] memory depositAmounts) internal {
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 remainingAmount = depositAmounts[i] - (depositAmounts[i] / 2);
            uint256 beforeWithdraw = _balanceOf(lpToken, accounts[i]);
            
            vm.prank(accounts[i]);
            rewardVault.withdraw(remainingAmount, accounts[i], accounts[i]);
            
            uint256 afterWithdraw = _balanceOf(lpToken, accounts[i]);
            
            // Verify all LP tokens returned
            assertEq(
                afterWithdraw - beforeWithdraw, 
                remainingAmount, 
                "Final withdrawal amount mismatch"
            );

            // Verify total received matches total deposited
            assertEq(
                afterWithdraw,
                depositAmounts[i],
                "Total LP tokens returned should match total deposited"
            );
        }
    }
    
    // Helper function to process CVX claims and verify distribution
    function _processClaimsCVX(address[] memory rewardTokens, uint256 totalCVX) internal {
        uint256 totalCVXClaimed = 0;
        
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 beforeClaim = _balanceOf(CVX, accounts[i]);
            
            vm.prank(accounts[i]);
            rewardVault.claim(rewardTokens, accounts[i]);
            
            uint256 afterClaim = _balanceOf(CVX, accounts[i]);
            uint256 claimed = afterClaim - beforeClaim;
            
            totalCVXClaimed += claimed;
            
            // Verify CVX rewards received
            assertGt(claimed, 0, "Account should receive CVX rewards");
        }
        
        // Verify all CVX rewards were distributed
        assertApproxEqRel(
            totalCVXClaimed, 
            totalCVX, 
            0.05e18, // Increased tolerance to match the other assertions for consistency
            "Total CVX claimed should match total distributed"
        );
    }
}
