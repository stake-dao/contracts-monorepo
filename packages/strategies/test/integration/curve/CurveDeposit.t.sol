// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/integration/curve/BaseCurveTest.sol";
import "src/integrations/curve/CurveAllocator.sol";

abstract contract CurveDepositTest is BaseCurveTest {
    constructor(uint256 _pid) BaseCurveTest(_pid) {}

    address public account;
    CurveAllocator public curveAllocator;

    function setUp() public override {
        super.setUp();

        /// 0. Deploy the allocator contract.
        curveAllocator = new CurveAllocator(address(locker), address(gateway), address(convexSidecarFactory));

        /// 1. Set the allocator.
        protocolController.setAllocator(protocolId, address(curveAllocator));

        /// 2. Deploy the Reward Vault contract through the factory.
        (address _rewardVault, address _rewardReceiver, address _sidecar) = curveFactory.create(pid);

        rewardVault = RewardVault(_rewardVault);
        rewardReceiver = RewardReceiver(_rewardReceiver);
        convexSidecar = ConvexSidecar(_sidecar);

        /// 3. Set up the account.
        account = makeAddr("Account");
        deal(lpToken, account, totalSupply);

        /// 4. Approve the reward vault.
        vm.prank(account);
        IERC20(lpToken).approve(address(rewardVault), totalSupply);
    }

    function test_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < totalSupply / 2);

        /// 1. Deposit the amount.
        vm.prank(account);
        rewardVault.deposit(amount, account);

        /// 2. Check the pending rewards.
        assertEq(accountant.getPendingRewards(account), 0);
        assertEq(rewardVault.balanceOf(account), amount);
        assertEq(rewardVault.totalSupply(), amount);

        /// 3. Check the overall balance of the gauge through the strategy.
        assertEq(curveStrategy.balanceOf(address(gauge)), amount);
    }
}