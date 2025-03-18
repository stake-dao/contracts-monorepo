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

    function test_deposit(uint256 amount) public {
        vm.assume(amount > 1e18);
        vm.assume(amount < (totalSupply / NUM_ACCOUNTS) / 2);

        /// Deal some extra rewards to the reward receiver.
        uint256 totalCVX = 1_000_000e18;
        deal(CVX, address(rewardReceiver), totalCVX);

        // Track total deposits and expected rewards
        uint256 totalDeposited = 0;
        uint256[] memory depositAmounts = new uint256[](NUM_ACCOUNTS);

        /// 1. Deposit amounts for each account (with slight variations)
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 accountAmount = amount * (i + 1) / NUM_ACCOUNTS;
            depositAmounts[i] = accountAmount;
            totalDeposited += accountAmount;

            vm.prank(accounts[i]);
            rewardVault.deposit(accountAmount, accounts[i]);
        }

        uint256 expectedRewards = _inflateRewards(address(gauge), 10_000e18);

        // Check the overall balance of the gauge through the strategy.
        assertEq(curveStrategy.balanceOf(address(gauge)), totalDeposited);

        /// Set up the harvester.
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);

        /// Empty arrays as we don't need extra datas for Curve.
        bytes[] memory harvestData = new bytes[](1);

        /// Harvest the rewards.
        vm.prank(harvester);
        accountant.harvest(gauges, harvestData);

        // Track total rewards claimed by all accounts
        uint256 totalAccountRewards = 0;

        // Each account claims their rewards
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            vm.prank(accounts[i]);
            accountant.claim(gauges, harvestData);

            uint256 accountBalance = _balanceOf(rewardToken, accounts[i]);
            totalAccountRewards += accountBalance;

            // Check each account received rewards
            assertGt(accountBalance, 0);
        }

        uint256 balanceOfHarvester = _balanceOf(rewardToken, harvester);
        uint256 balanceOfAccountant = _balanceOf(rewardToken, address(accountant));

        /// Check the pending rewards.
        assertGt(balanceOfHarvester, 0);
        assertGt(totalAccountRewards, 0);
        assertGt(balanceOfAccountant, 0);
        assertEq(balanceOfAccountant + totalAccountRewards + balanceOfHarvester, expectedRewards);

        /// Claim the extra rewards.
        convexSidecar.claimExtraRewards();

        /// Distribute the rewards.
        rewardReceiver.distributeRewards();

        address[] memory rewardTokens = rewardVault.getRewardTokens();

        skip(1 weeks);

        // Each account claims their CVX rewards
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 accountAmount = depositAmounts[i];

            vm.prank(accounts[i]);
            rewardVault.claim(rewardTokens, accounts[i]);

            totalClaimed += _balanceOf(CVX, accounts[i]);
        }

        assertApproxEqRel(totalClaimed, totalCVX, 0.0001e18);
    }

    function test_multipleUsersDepositWithdraw() public {
        // Use a fixed amount for deterministic testing
        uint256 baseAmount = 10e18;

        // Initial balances before any operations
        uint256[] memory initialBalances = new uint256[](NUM_ACCOUNTS);
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            initialBalances[i] = IERC20(lpToken).balanceOf(accounts[i]);
        }

        // Each account deposits a different amount
        uint256[] memory depositAmounts = new uint256[](NUM_ACCOUNTS);
        uint256 totalDeposited = 0;

        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // Each account deposits a different amount
            depositAmounts[i] = baseAmount * (i + 1);
            totalDeposited += depositAmounts[i];

            vm.prank(accounts[i]);
            rewardVault.deposit(depositAmounts[i], accounts[i]);

            // Verify the account's LP token balance decreased
            assertEq(
                IERC20(lpToken).balanceOf(accounts[i]),
                initialBalances[i] - depositAmounts[i],
                "LP token balance should decrease after deposit"
            );

            // Verify the account's shares in the vault
            assertEq(
                rewardVault.balanceOf(accounts[i]),
                depositAmounts[i],
                "Reward vault balance should match deposit amount"
            );
        }

        // Verify total deposits
        assertEq(
            curveStrategy.balanceOf(address(gauge)), totalDeposited, "Total gauge balance should match total deposits"
        );

        // Now have accounts withdraw in a different order
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // Withdraw in reverse order (last account first)
            uint256 accountIndex = NUM_ACCOUNTS - 1 - i;
            uint256 withdrawAmount = depositAmounts[accountIndex];

            // Withdraw the full amount
            vm.prank(accounts[accountIndex]);
            rewardVault.withdraw(withdrawAmount, accounts[accountIndex], accounts[accountIndex]);

            // Verify the account's LP token balance is restored
            assertEq(
                IERC20(lpToken).balanceOf(accounts[accountIndex]),
                initialBalances[accountIndex],
                "LP token balance should be restored after full withdrawal"
            );

            // Verify the account's shares in the vault are zero
            assertEq(
                rewardVault.balanceOf(accounts[accountIndex]),
                0,
                "Reward vault balance should be zero after full withdrawal"
            );

            // Update total deposited
            totalDeposited -= withdrawAmount;

            // Verify the updated total in the gauge
            assertEq(
                curveStrategy.balanceOf(address(gauge)),
                totalDeposited,
                "Gauge balance should decrease after withdrawal"
            );
        }

        // Verify all funds have been withdrawn
        assertEq(curveStrategy.balanceOf(address(gauge)), 0, "Gauge balance should be zero after all withdrawals");
    }
}
