// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/Base.t.sol";

contract AccountantTest is BaseTest {
    using Math for uint256;

    function setUp() public override {
        super.setUp();
    }

    function test_constructor() public view {
        assertEq(accountant.REGISTRY(), address(registry));
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
        accountant.checkpoint(address(stakingToken), address(0), account, amount, 0, false);

        /// Check that the accountant has the correct balance.
        uint256 totalSupply = accountant.totalSupply(address(this));
        uint256 balance = accountant.balanceOf(address(this), account);
        uint256 accountPendingRewards = accountant.getPendingRewards(address(this), account);

        assertEq(balance, amount);
        assertEq(totalSupply, amount);
        assertEq(accountPendingRewards, 0);

        /// Burn for account.
        accountant.checkpoint(address(stakingToken), account, address(0), amount, 0, true);

        /// Check that the accountant has the correct balance.
        assertEq(accountant.totalSupply(address(this)), 0);
        assertEq(accountant.balanceOf(address(this), account), 0);
    }

    function test_transfer_between_users(uint128 amount) public {
        address userA = address(0x1);
        address userB = address(0x2);

        // Initial mint to userA
        accountant.checkpoint(address(stakingToken), address(0), userA, amount, 0, false);
        assertEq(accountant.balanceOf(address(this), userA), amount);
        assertEq(accountant.balanceOf(address(this), userB), 0);

        // Transfer from A to B
        accountant.checkpoint(address(stakingToken), userA, userB, amount, 0, false);

        // Verify balances
        assertEq(accountant.balanceOf(address(this), userA), 0);
        assertEq(accountant.balanceOf(address(this), userB), amount);
        assertEq(accountant.totalSupply(address(this)), amount);
    }

    function test_checkpoint_with_pending_rewards(uint128 amount, uint128 rewards) public {
        // Ensure reasonable bounds for testing
        vm.assume(amount >= 1e18 && amount <= 1e24);
        vm.assume(rewards >= 1e18 && rewards <= 1e24);

        // vm.assume(uint256(rewards).mulDiv(accountant.getTotalFeePercent(), 1e18) >= 1e6);
        address user = address(0x1);

        // Initial mint to user
        accountant.checkpoint(address(stakingToken), address(0), user, amount, 0, false);

        // Trigger pending rewards
        accountant.checkpoint(address(stakingToken), address(0), user, 0, rewards, false);

        // Check rewards are properly accounted
        assertApproxEqRel(
            accountant.getPendingRewards(address(this), user),
            uint256(rewards) - uint256(rewards).mulDiv(accountant.getTotalFeePercent(), 1e18),
            1e15
        );

        assertEq(accountant.protocolFeesAccrued(), 0);
    }

    // function test_checkpoint_zero_supply(uint128 rewards) public {
    // vm.assume(rewards >= 1e6 && rewards <= 1e24);

    // // Should not revert with zero supply
    // accountant.checkpoint(address(stakingToken), address(0), address(0), 0, rewards, false);
    // assertEq(accountant.protocolFeesAccrued(), 0);
    // }

    // function test_harvest_process(uint128 amount, uint128 rewards) public {
    // // Ensure reasonable bounds for testing
    // vm.assume(amount >= 1e6 && amount <= 1e24);
    // vm.assume(rewards >= 1e6 && rewards <= 1e24);
    // vm.assume(uint256(rewards).mulDiv(accountant.getTotalFeePercent(), 1e18) >= 1e6);
    // address user = address(0x1);

    // // Initial mint to user
    // accountant.checkpoint(address(stakingToken), address(0), user, amount, 0, false);

    // // Mock rewards and harvest
    // deal(address(rewardToken), address(this), rewards);
    // rewardToken.approve(address(accountant), rewards);

    // address[] memory vaults = new address[](1);
    // vaults[0] = address(this);
    // bytes[] memory harvestData = new bytes[](1);
    // harvestData[0] = "";

    // accountant.harvest(vaults, harvestData);

    // // Verify harvest fees
    // uint256 expectedProtocolFees = uint256(rewards).mulDiv(accountant.getProtocolFeePercent(), 1e18);
    // uint256 expectedHarvestFees = uint256(rewards).mulDiv(accountant.getHarvestFeePercent(), 1e18);
    // assertEq(accountant.protocolFeesAccrued(), expectedProtocolFees + expectedHarvestFees);
    // }

    // function test_claim_rewards(uint128 amount, uint128 rewards) public {
    // // Ensure reasonable bounds for testing
    // vm.assume(amount >= 1e6 && amount <= 1e24);
    // vm.assume(rewards >= 1e6 && rewards <= 1e24);
    // vm.assume(uint256(rewards).mulDiv(accountant.getTotalFeePercent(), 1e18) >= 1e6);
    // address user = address(0x1);

    // // Initial mint to user
    // accountant.checkpoint(address(stakingToken), address(0), user, amount, 0, false);

    // // Generate rewards
    // accountant.checkpoint(address(stakingToken), address(0), address(0), 0, rewards, false);

    // // Mock reward token balance
    // deal(address(rewardToken), address(accountant), rewards);

    // // Claim rewards
    // vm.prank(user);
    // address[] memory vaults = new address[](1);
    // vaults[0] = address(this);
    // bytes[] memory harvestData = new bytes[](1);
    // harvestData[0] = "";
    // accountant.claim(vaults, user, harvestData);

    // // Verify rewards received
    // uint256 expectedRewards = uint256(rewards) - uint256(rewards).mulDiv(accountant.getTotalFeePercent(), 1e18);
    // assertEq(rewardToken.balanceOf(user), expectedRewards);
    // }

    // function test_claim_no_pending_rewards() public {
    // address user = address(0x1);
    // vm.prank(user);
    // address[] memory vaults = new address[](1);
    // vaults[0] = address(this);
    // bytes[] memory harvestData = new bytes[](1);
    // harvestData[0] = "";

    // vm.expectRevert(Accountant.NoPendingRewards.selector);
    // accountant.claim(vaults, user, harvestData);
    // }

    // function test_protocol_fee_management(uint128 amount, uint128 rewards) public {
    // // Ensure reasonable bounds for testing
    // vm.assume(amount >= 1e6 && amount <= 1e24);
    // vm.assume(rewards >= 1e6 && rewards <= 1e24);
    // vm.assume(uint256(rewards).mulDiv(accountant.getTotalFeePercent(), 1e18) >= 1e6);
    // address user = address(0x1);

    // // Initial mint and generate rewards
    // accountant.checkpoint(address(stakingToken), address(0), user, amount, 0, false);
    // accountant.checkpoint(address(stakingToken), address(0), address(0), 0, rewards, false);

    // // Mock reward token balance
    // deal(address(rewardToken), address(accountant), rewards);

    // // Verify protocol fees can be claimed
    // uint256 expectedFees = uint256(rewards).mulDiv(accountant.getTotalFeePercent(), 1e18);
    // assertEq(accountant.protocolFeesAccrued(), expectedFees);

    // // Claim protocol fees
    // accountant.claimProtocolFees();
    // assertEq(accountant.protocolFeesAccrued(), 0);
    // }

    // function test_access_control() public {
    // // Test OnlyVault modifier
    // vm.expectRevert(Accountant.OnlyVault.selector);
    // vm.prank(address(0x1));
    // accountant.checkpoint(address(stakingToken), address(0), address(0), 0, 0, false);

    // // Test OnlyOwner modifier
    // vm.expectRevert(Ownable.OwnableUnauthorizedAccount.selector);
    // vm.prank(address(0x1));
    // accountant.setProtocolFeePercent(0.1e18);
    // }

    // function test_edge_cases(uint128 amount) public {
    // // Use a reasonable minimum amount for testing
    // vm.assume(amount >= 1e6 && amount <= 1e24);
    // address user = address(0x1);

    // // Test zero supply vault
    // accountant.checkpoint(address(stakingToken), address(0), address(0), 0, amount, false);

    // // Test large reward near MAX_FEE_PERCENT
    // uint256 largeReward = type(uint128).max;
    // accountant.checkpoint(address(stakingToken), address(0), user, amount, 0, false);
    // accountant.checkpoint(address(stakingToken), address(0), address(0), 0, largeReward, false);

    // // Verify no overflow
    // assertTrue(accountant.protocolFeesAccrued() > 0);
    // }
}
