// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/Base.t.sol";

contract AccountantTest is BaseTest {
    using Math for uint256;

    function setUp() public override {
        super.setUp();
    }

    function test_constructor() public view {
        assertEq(accountant.PROTOCOL_CONTROLLER(), address(registry));
        assertEq(accountant.REWARD_TOKEN(), address(rewardToken));
        assertEq(accountant.protocolFeesAccrued(), 0);

        /// Check the fee receiver is set
        assertEq(accountant.HARVEST_URGENCY_THRESHOLD(), 0);
        assertEq(accountant.getCurrentHarvestFee(), accountant.getHarvestFeePercent());

        /// 15% protocol fee
        assertEq(accountant.getProtocolFeePercent(), 0.15e18);

        /// 0.5% harvest fee
        assertEq(accountant.getHarvestFeePercent(), 0.005e18);

        /// 15% protocol fee + 0.5% harvest fee
        assertEq(accountant.getTotalFeePercent(), 0.155e18);

        /// Owner is the deployer
        assertEq(accountant.owner(), address(this));
    }

    function test_mint_and_burn_checkpoint(uint128 amount, address account) public {
        vm.assume(account != address(0));
        vm.assume(account != address(this));
        vm.assume(account != address(accountant));

        /// Account for the mint.
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            account,
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            false
        );

        /// Check that the accountant has the correct balance.
        uint256 totalSupply = accountant.totalSupply(address(this));
        uint256 balance = accountant.balanceOf(address(this), account);
        uint256 accountPendingRewards = accountant.getPendingRewards(address(this), account);

        assertEq(balance, amount);
        assertEq(totalSupply, amount);
        assertEq(accountPendingRewards, 0);

        /// Burn for account.
        accountant.checkpoint(
            address(stakingToken),
            account,
            address(0),
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            true
        );

        /// Check that the accountant has the correct balance.
        assertEq(accountant.totalSupply(address(this)), 0);
        assertEq(accountant.balanceOf(address(this), account), 0);
    }

    function test_transfer_between_users(uint128 amount) public {
        address userA = address(0x1);
        address userB = address(0x2);

        // Initial mint to userA
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            userA,
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            false
        );
        assertEq(accountant.balanceOf(address(this), userA), amount);
        assertEq(accountant.balanceOf(address(this), userB), 0);

        // Transfer from A to B
        accountant.checkpoint(
            address(stakingToken),
            userA,
            userB,
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            false
        );

        // Verify balances
        assertEq(accountant.balanceOf(address(this), userA), 0);
        assertEq(accountant.balanceOf(address(this), userB), amount);
        assertEq(accountant.totalSupply(address(this)), amount);
    }

    function test_checkpoint_with_pending_rewards(uint128 amount, uint128 rewards) public {
        // Ensure reasonable bounds for testing
        vm.assume(amount >= 1e18 && amount <= 1e24);
        vm.assume(rewards > 0 && rewards <= 1e24);

        address user = address(0x1);

        // Initial mint to user
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            user,
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            false
        );

        // Trigger pending rewards
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            user,
            0,
            IStrategy.PendingRewards({feeSubjectAmount: rewards, totalAmount: rewards}),
            false
        );

        // Calculate expected rewards based on MIN_MEANINGFUL_REWARDS threshold
        uint256 expectedRewards;
        if (rewards >= accountant.MIN_MEANINGFUL_REWARDS()) {
            expectedRewards = uint256(rewards) - uint256(rewards).mulDiv(accountant.getTotalFeePercent(), 1e18);

            // Check that vault pending rewards are correctly updated
            uint256 totalAmount = accountant.getPendingRewards(address(this));
            assertEq(totalAmount, rewards);
        } else {
            expectedRewards = 0; // No rewards distributed if below threshold
        }

        // Check rewards are properly accounted
        assertApproxEqRel(accountant.getPendingRewards(address(this), user), expectedRewards, 1e15);

        // Check that protocol fees are not yet accrued since rewards weren't harvested
        assertEq(accountant.protocolFeesAccrued(), 0);

        /// Add MEANINGFUL_REWARDS to the rewards.
        rewards += uint128(accountant.MIN_MEANINGFUL_REWARDS());

        // Trigger a new pending rewards.
        /// This should trigger a new pending rewards, but not double account the rewards if already accounted.
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            user,
            0,
            IStrategy.PendingRewards({feeSubjectAmount: rewards, totalAmount: rewards}),
            false
        );

        // Calculate new expected rewards after adding MIN_MEANINGFUL_REWARDS
        uint256 newExpectedRewards = uint256(rewards) - uint256(rewards).mulDiv(accountant.getTotalFeePercent(), 1e18);

        // Verify that rewards are properly updated and not double-counted
        assertApproxEqRel(accountant.getPendingRewards(address(this), user), newExpectedRewards, 1e15);

        // Verify vault's total pending rewards matches the new rewards amount
        uint256 totalAmount = accountant.getPendingRewards(address(this));
        assertEq(totalAmount, rewards);

        // Protocol fees should still be 0 since rewards haven't been harvested
        assertEq(accountant.protocolFeesAccrued(), 0);
    }

    function test_harvest(uint128 amount, uint128 rewards) public {
        // Ensure reasonable bounds for testing
        vm.assume(amount >= 1e6 && amount <= 1e24);
        vm.assume(rewards >= accountant.MIN_MEANINGFUL_REWARDS() && rewards <= 1e24);

        address[] memory vaults = new address[](1);
        vaults[0] = address(this);
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = abi.encode(rewards, 1e18);

        /// Test that the harvester is not set.
        registry.setHarvester(address(0));

        vm.expectRevert(Accountant.NoHarvester.selector);
        accountant.harvest(vaults, harvestData);

        registry.setHarvester(address(harvester));

        address user = address(0x1);
        address harvester = address(0x2);

        // Initial mint to user
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            user,
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            false
        );
        assertEq(accountant.totalSupply(address(this)), amount);

        /// Check that the reward token balance is 0.
        assertEq(rewardToken.balanceOf(harvester), 0);
        assertEq(rewardToken.balanceOf(address(accountant)), 0);

        /// Get the harvest fee.
        uint256 harvestFee = uint256(rewards).mulDiv(accountant.getCurrentHarvestFee(), 1e18);

        /// Since the balance is 0, the harvest fee should be to maximum.
        assertEq(accountant.getCurrentHarvestFee(), accountant.getHarvestFeePercent());

        /// Test that the harvest is successful.
        vm.prank(harvester);
        accountant.harvest(vaults, harvestData);

        /// Check that the reward token balance is correct.
        assertEq(rewardToken.balanceOf(harvester), harvestFee);
        assertEq(rewardToken.balanceOf(address(accountant)), rewards - harvestFee);

        /// Set the harvest urgency threshold to the rewards * 2.
        accountant.setHarvestUrgencyThreshold(rewards * 2);

        /// Harvest fee should be less than the maximum.
        assertGt(accountant.getCurrentHarvestFee(), 0);
        assertLt(accountant.getCurrentHarvestFee(), accountant.getHarvestFeePercent());

        /// Set the harvest urgency threshold to the rewards.
        accountant.setHarvestUrgencyThreshold(rewards - harvestFee);

        /// Harvest fee should be 0.
        assertEq(accountant.getCurrentHarvestFee(), 0);

        // Verify harvest fees
        uint256 expectedProtocolFees = uint256(rewards).mulDiv(accountant.getProtocolFeePercent(), 1e18);
        assertEq(accountant.protocolFeesAccrued(), expectedProtocolFees);

        /// Reset balance to 0 for simplicity.
        deal(address(rewardToken), address(accountant), 0);
        deal(address(rewardToken), address(harvester), 0);

        assertEq(rewardToken.balanceOf(address(accountant)), 0);
        assertEq(rewardToken.balanceOf(address(harvester)), 0);

        /// Set Fee Exemption.
        /// 2e18 means half of the rewards are exempted from fees.
        harvestData[0] = abi.encode(rewards, 2e18);

        /// Harvest fee should be taken from the full rewards.
        harvestFee = uint256(rewards).mulDiv(accountant.getCurrentHarvestFee(), 1e18);

        uint256 protocolFees = accountant.protocolFeesAccrued();

        /// Harvest again.
        vm.prank(harvester);
        accountant.harvest(vaults, harvestData);

        /// But protocol fees should be taken only from the half of the rewards.
        expectedProtocolFees = uint256(rewards).mulDiv(accountant.getProtocolFeePercent(), 1e18) / 2;

        /// Check that the reward token balance is correct.
        assertEq(rewardToken.balanceOf(harvester), harvestFee);
        assertEq(rewardToken.balanceOf(address(accountant)), rewards - harvestFee);

        /// Check that the protocol fees are correct.
        /// Difference should be really small because of the rounding of the MockHarvester.
        assertApproxEqAbs(accountant.protocolFeesAccrued(), protocolFees + expectedProtocolFees, 1);
    }

    function test_claim_rewards(uint128 amount, uint128 rewards) public {
        // Ensure reasonable bounds for testing
        vm.assume(amount >= 1e6 && amount <= 1e24);
        vm.assume(rewards >= accountant.MIN_MEANINGFUL_REWARDS() && rewards <= 1e24);

        address user = address(0x1);
        address user2 = address(0x2);

        address[] memory vaults = new address[](1);
        vaults[0] = address(this);
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = abi.encode(rewards, 1e18);

        // Initial mint to user
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            user,
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            false
        );

        // Generate rewards
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            user,
            0,
            IStrategy.PendingRewards({feeSubjectAmount: rewards, totalAmount: rewards}),
            false
        );

        vm.prank(user2);
        vm.expectRevert(Accountant.NoPendingRewards.selector);
        accountant.claim(vaults, user2, harvestData);

        /// Get the pending rewards from the checkpoint.
        uint256 pendingRewards = accountant.getPendingRewards(address(this), user);

        /// Since the user harvest as he claims, he also gets the harvest fee.
        uint256 harvestFee = uint256(rewards).mulDiv(accountant.getCurrentHarvestFee(), 1e18);

        vm.prank(user);
        accountant.claim(vaults, user, harvestData);

        // Verify rewards received.
        assertEq(rewardToken.balanceOf(user), pendingRewards + harvestFee);

        /// No pending rewards.
        harvestData[0] = "";

        vm.prank(user);
        vm.expectRevert(Accountant.NoPendingRewards.selector);
        accountant.claim(vaults, user, harvestData);
    }

    function test_protocol_fee_management(uint128 amount, uint128 rewards) public {
        // Ensure reasonable bounds for testing
        vm.assume(amount >= 1e6 && amount <= 1e24);
        vm.assume(rewards >= accountant.MIN_MEANINGFUL_REWARDS() && rewards <= 1e24);

        address user = address(0x1);
        address feeReceiver = address(0x2);

        // Initial mint and generate rewards
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            user,
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            true
        );
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            address(0),
            0,
            IStrategy.PendingRewards({feeSubjectAmount: rewards, totalAmount: rewards}),
            true
        );

        // Mock reward token balance
        deal(address(rewardToken), address(accountant), rewards);

        // Verify protocol fees can be claimed
        uint256 expectedFees = uint256(rewards).mulDiv(accountant.getProtocolFeePercent(), 1e18);
        assertEq(accountant.protocolFeesAccrued(), expectedFees);

        // Claim protocol fees
        vm.expectRevert(Accountant.NoFeeReceiver.selector);
        accountant.claimProtocolFees();

        // Set the fee receiver
        registry.setFeeReceiver(feeReceiver);

        // Claim protocol fees
        accountant.claimProtocolFees();
        assertEq(accountant.protocolFeesAccrued(), 0);
        assertEq(rewardToken.balanceOf(feeReceiver), expectedFees);
    }

    function test_access_control() public {
        address[] memory vaults = new address[](1);
        vaults[0] = address(this);
        bytes[] memory harvestData = new bytes[](1);

        vm.expectRevert(Accountant.OnlyAllowed.selector);
        vm.prank(address(0x1));
        accountant.claim(vaults, address(this), address(0x1), harvestData);

        // Test OnlyVault modifier
        vm.expectRevert(Accountant.OnlyVault.selector);
        vm.prank(address(0x1));
        accountant.checkpoint(
            address(stakingToken),
            address(0),
            address(0),
            0,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            false
        );

        // Test OnlyOwner modifier
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x1)));
        vm.prank(address(0x1));
        accountant.setProtocolFeePercent(0.1e18);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x1)));
        vm.prank(address(0x1));
        accountant.setHarvestFeePercent(0.1e18);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x1)));
        vm.prank(address(0x1));
        accountant.setHarvestUrgencyThreshold(0.1e18);
    }
}
