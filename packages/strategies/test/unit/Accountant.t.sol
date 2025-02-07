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
        vm.assume(amount > 0);
        vm.assume(account != address(0));
        vm.assume(account != address(this));

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
}
