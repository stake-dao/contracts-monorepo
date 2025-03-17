// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/integration/curve/BaseCurveTest.sol";
import "src/integrations/curve/CurveAllocator.sol";

abstract contract CurveIntegrationTest is BaseCurveTest {
    constructor(uint256 _pid) BaseCurveTest(_pid) {}

    address public account = makeAddr("Account");
    address public harvester = makeAddr("Harvester");

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
        deal(lpToken, account, totalSupply);


        /// 5. Approve the reward vault.
        vm.prank(account);
        IERC20(lpToken).approve(address(rewardVault), totalSupply);
    }

    function test_deposit(uint256 amount) public {
        vm.assume(amount > 1e18);
        vm.assume(amount < totalSupply / 2);

        /// 4. Deal some extra rewards to the reward receiver.
        deal(CVX, address(rewardReceiver), amount);

        /// 1. Deposit the amount.
        vm.prank(account);
        rewardVault.deposit(amount, account);

        uint256 expectedRewards = gauge.integrate_fraction(LOCKER) - IMinter(MINTER).minted(LOCKER, address(gauge));

        if (expectedRewards == 0) {
            expectedRewards = _inflateRewards(address(gauge));
        }

        // 3. Check the overall balance of the gauge through the strategy.
        assertEq(curveStrategy.balanceOf(address(gauge)), amount);

        /// 4. Set up the harvester.
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);

        /// Empty arrays as we don't need extra datas for Curve.
        bytes[] memory harvestData = new bytes[](1);

        /// 4. Harvest the rewards.
        vm.prank(harvester);
        accountant.harvest(gauges, harvestData);

        vm.prank(account);
        accountant.claim(gauges, harvestData);

        uint256 balanceOfHarvester = _balanceOf(rewardToken, harvester);
        uint256 balanceOfAccount = _balanceOf(rewardToken, account);
        uint256 balanceOfAccountant = _balanceOf(rewardToken, address(accountant));

        /// 5. Check the pending rewards.
        assertGt(balanceOfHarvester, 0);
        assertGt(balanceOfAccount, 0);
        assertGt(balanceOfAccountant, 0);
        assertEq(balanceOfAccountant + balanceOfAccount + balanceOfHarvester, expectedRewards);

        /// 6. Claim the extra rewards.
        convexSidecar.claimExtraRewards();

        /// 7. Distribute the rewards.
        rewardReceiver.distributeRewards();

        address[] memory rewardTokens = rewardVault.getRewardTokens();

        skip(1 weeks);

        vm.prank(account);
        rewardVault.claim(rewardTokens, account);
        assertApproxEqRel(_balanceOf(CVX, account), amount, 0.0001e18); // 0.01%
    }
}
