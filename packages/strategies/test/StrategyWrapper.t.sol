// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import {CurveMainnetIntegrationTest} from "test/integration/curve/mainnet/CurveMainnetIntegration.t.sol";
import {RewardVault} from "src/RewardVault.sol";
import {StrategyWrapper} from "src/wrappers/StrategyWrapper.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

contract StrategyWrapperIntegrationTest is CurveMainnetIntegrationTest {
    StrategyWrapper internal wrapper;
    MorphoMock internal morpho;

    constructor() CurveMainnetIntegrationTest() {}

    // @dev Only fuzz a single account position
    function MAX_ACCOUNT_POSITIONS() public virtual override returns (uint256) {
        return 1;
    }

    // @dev Only use one Curve pool for our test
    function poolIds() public pure override returns (uint256[] memory) {
        uint256[] memory _poolIds = new uint256[](1);
        _poolIds[0] = 68;
        return _poolIds;
    }

    // @dev Test the complete protocol lifecycle with one account interacting directly with the protocol and one interacting with the morpho wrapper
    function test_complete_protocol_lifecycle() public override {
        ///////////////////////////////////////////////////////////////
        // --- SETUP
        ///////////////////////////////////////////////////////////////

        // Fuzz a single AccountPosition and reward amount
        (AccountPosition[] memory _accountPositions, uint256[] memory _rewards) = _generateAccountPositionsAndRewards();
        AccountPosition memory position = _accountPositions[0];
        uint256 rewardAmount = _rewards[0];

        // Set the two users that will interact with the protocol
        address directUser = position.account;
        address wrapperUser = makeAddr("WrapperUser");

        // Deploy the reward vault
        (RewardVault[] memory vaults,) = deployRewardVaults();
        RewardVault rewardVault = vaults[0];
        vm.label(address(rewardVault), "RewardVault");

        // Deploy the mock Morpho contract
        morpho = new MorphoMock();

        // Deploy the Morpho Strategy Wrapper and store the reward vault
        wrapper = new StrategyWrapper(rewardVault, address(morpho), address(this));
        vm.label(address(wrapper), "MorphoWrapper");

        // Add an extra reward token to the reward vault
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.isRegistrar.selector, address(this)),
            abi.encode(true)
        );
        rewardVault.addRewardToken(Common.WETH, address(this));

        ///////////////////////////////////////////////////////////////
        // --- TESTS
        ///////////////////////////////////////////////////////////////

        // 1. Both users deposit to the vault
        deposit(rewardVault, directUser, position.baseAmount);
        _depositIntoWrapper(rewardVault, wrapperUser, position.baseAmount);

        // 2. Deposit all the wrapper ERC20 tokens into Morpho with the wrapper user
        _depositIntoMorpho(wrapperUser, position.baseAmount);

        // Make sure the balances post-deposit are correct
        assertEq(rewardVault.balanceOf(directUser), position.baseAmount, "Direct user: vault balance after deposit");
        assertEq(rewardVault.balanceOf(wrapperUser), 0, "Wrapper user: vault balance after wrapping");
        assertEq(rewardVault.balanceOf(address(wrapper)), position.baseAmount, "Wrapper holds vault shares");
        assertEq(wrapper.balanceOf(wrapperUser), 0, "Wrapper user: wrapper balance after wrapping");
        assertEq(wrapper.balanceOf(address(morpho)), position.baseAmount, "Wrapper user: Morpho balance after wrapping");

        // 3. Deposit some extra reward token into the reward vault
        uint128 extraRewardAmount = 1e20;
        deal(Common.WETH, address(this), extraRewardAmount);
        IERC20(Common.WETH).approve(address(rewardVault), extraRewardAmount);
        rewardVault.depositRewards(Common.WETH, extraRewardAmount);
        uint256 extraRewardDepositingTimestamp = block.timestamp;

        // 4. Simulate rewards and harvest
        simulateRewards(rewardVault, rewardAmount);
        deal(address(rewardToken), address(accountant), rewardAmount);
        skip(2 days);
        harvest();

        // 5. Both users claim rewards
        claim(rewardVault, directUser);
        _claimFromWrapper(wrapperUser);
        _claimFromWrapper(address(morpho)); // in case Morpho is malicious and tried to claim rewards

        // Make sure the claimed rewards are the same
        assertNotEq(_balanceOf(rewardToken, directUser), 0, "Direct user: should have claimed rewards");
        assertNotEq(_balanceOf(rewardToken, wrapperUser), 0, "Wrapper user: should have claimed rewards");
        assertEq(_balanceOf(rewardToken, address(morpho)), 0, "Morpho: should have no claimed rewards"); // morpho claimed nothing
        assertApproxEqRel(
            _balanceOf(rewardToken, directUser),
            _balanceOf(rewardToken, wrapperUser),
            1e16, // 1% (rounding)
            "Claimed rewards should match"
        );

        // 6. Withdraw the wrapper ERC20 tokens from Morpho for the wrapper user
        _withdrawFromMorpho(wrapperUser, morpho.balances(wrapperUser, address(wrapper)));
        assertEq(morpho.balances(wrapperUser, address(wrapper)), 0, "Morpho: should have no wrapper ERC20 tokens");
        assertEq(
            wrapper.balanceOf(wrapperUser),
            position.baseAmount,
            "Wrapper user: wrapper balance after withdrawing from Morpho"
        );
        assertEq(wrapper.balanceOf(address(morpho)), 0, "Morpho: wrapper balance after withdrawing from Morpho");

        // 7. Both users deposit more
        deposit(rewardVault, directUser, position.additionalAmount);
        _depositIntoWrapper(rewardVault, wrapperUser, position.additionalAmount);

        uint256 expected = position.baseAmount + position.additionalAmount;
        assertEq(rewardVault.balanceOf(directUser), expected, "Direct user: vault balance after additional deposit");
        assertEq(rewardVault.balanceOf(wrapperUser), 0, "Wrapper user: vault balance after wrapping again");
        assertEq(wrapper.balanceOf(wrapperUser), expected, "Wrapper user: wrapper balance after wrapping again");
        assertEq(
            rewardVault.balanceOf(address(wrapper)), expected, "Wrapper holds vault shares after additional deposit"
        );

        // 8. Both users withdraw partially
        withdraw(rewardVault, directUser, position.partialWithdrawAmount);
        _withdrawFromWrapper(wrapperUser, position.partialWithdrawAmount);

        expected = expected - position.partialWithdrawAmount;
        assertEq(rewardVault.balanceOf(directUser), expected, "Direct user: vault balance after partial withdraw");
        assertEq(wrapper.balanceOf(wrapperUser), expected, "Wrapper user: wrapper balance after partial withdraw");
        assertEq(rewardVault.balanceOf(address(wrapper)), expected, "Wrapper holds vault shares after partial withdraw");

        // 9. Simulate more rewards and harvest
        simulateRewards(rewardVault, rewardAmount / 2);
        deal(address(rewardToken), address(accountant), rewardAmount / 2);
        skip(1 days);
        harvest();

        // 10. Both users claim again
        claim(rewardVault, directUser);
        _claimFromWrapper(wrapperUser);

        assertApproxEqRel(
            _balanceOf(rewardToken, directUser),
            _balanceOf(rewardToken, wrapperUser),
            1e15, // 0.1% (rounding)
            "Claimed rewards after more rewards should match"
        );

        // 11. Both users withdraw all
        withdraw(rewardVault, directUser, rewardVault.balanceOf(directUser));
        _withdrawFromWrapper(wrapperUser, wrapper.balanceOf(wrapperUser));

        assertEq(rewardVault.balanceOf(directUser), 0, "Direct user: vault balance after final withdraw");
        assertEq(wrapper.balanceOf(wrapperUser), 0, "Wrapper user: wrapper balance after final withdraw");
        assertEq(rewardVault.balanceOf(address(wrapper)), 0, "Wrapper holds no vault shares after final withdraw");
        assertEq(
            rewardVault.balanceOf(wrapperUser),
            expected + position.partialWithdrawAmount,
            "Wrapper user should have all vault shares after final withdraw"
        );
        assertEq(
            IERC20(rewardVault.asset()).balanceOf(directUser),
            position.baseAmount + position.additionalAmount,
            "Direct user: should get back of all deposited assets after final withdraw"
        );
        assertEq(
            IERC20(rewardVault.asset()).balanceOf(wrapperUser),
            0,
            "Wrapper user: should not get back of any deposited assets after final withdraw as still in the vault"
        );
        assertApproxEqRel(
            _balanceOf(rewardToken, directUser),
            _balanceOf(rewardToken, wrapperUser),
            1e15, // 0.1%
            "Final claimed rewards should match between direct and wrapper user"
        );

        // 12. Wrapped user withdraws from the vault
        withdraw(rewardVault, wrapperUser, rewardVault.balanceOf(wrapperUser));
        assertEq(
            IERC20(rewardVault.asset()).balanceOf(wrapperUser),
            position.baseAmount + position.additionalAmount,
            "Wrapper user: should get back of all deposited assets after final withdraw"
        );
        assertEq(
            IERC20(rewardVault.asset()).balanceOf(wrapperUser),
            IERC20(rewardVault.asset()).balanceOf(directUser),
            "Both users should have the same final balance of asset token"
        );

        // 13. Claim the extra reward token balance of the wrapper user after withdrawing from the wrapper contract.
        address[] memory tokens = new address[](1);
        tokens[0] = Common.WETH;

        _claimExtraRewardsFromWrapper(wrapperUser);
        uint256 expectedExtraRewardBalance =
            ((block.timestamp - extraRewardDepositingTimestamp) * extraRewardAmount) / (7 days * 2);
        uint256 wrapperUserRealExtraRewardBalance = IERC20(Common.WETH).balanceOf(wrapperUser);
        assertApproxEqRel(
            wrapperUserRealExtraRewardBalance,
            expectedExtraRewardBalance,
            1e17, // 0.1% tolerance
            "Wrapper user: should have the expected extra reward token balance"
        );

        // 14. Claim the extra reward token balance of the direct user
        vm.prank(directUser);
        rewardVault.claim(tokens, directUser);
        uint256 directUserRealExtraRewardBalance = IERC20(Common.WETH).balanceOf(directUser);

        assertApproxEqRel(
            directUserRealExtraRewardBalance,
            expectedExtraRewardBalance,
            1e17, // 0.1% tolerance
            "Direct user: should have the expected extra reward token balance"
        );

        // 15. Make sure the wrapper user cannot claim extra rewards unlocked after he left the wrapper contract
        skip(10 days);
        _claimExtraRewardsFromWrapper(wrapperUser);
        assertEq(IERC20(Common.WETH).balanceOf(wrapperUser), wrapperUserRealExtraRewardBalance);
    }

    /// @notice Test that re-depositing into the wrapper automatically claims pending rewards to prevent loss
    function test_reDepositAutoClaimsRewards() external {
        ///////////////////////////////////////////////////////////////
        // --- SETUP
        ///////////////////////////////////////////////////////////////

        // Generate test data
        (AccountPosition[] memory _accountPositions, uint256[] memory _rewards) = _generateAccountPositionsAndRewards();
        AccountPosition memory position = _accountPositions[0];
        uint256 rewardAmount = _rewards[0];

        address user = position.account;
        uint256 initialDeposit = position.baseAmount;
        uint256 additionalDeposit = position.additionalAmount;

        // Deploy vault and wrapper
        (RewardVault[] memory vaults,) = deployRewardVaults();
        RewardVault rewardVault = vaults[0];
        wrapper = new StrategyWrapper(rewardVault, address(this), address(this));

        // Add extra reward token
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.isRegistrar.selector, address(this)),
            abi.encode(true)
        );
        rewardVault.addRewardToken(Common.WETH, address(this));

        ///////////////////////////////////////////////////////////////
        // --- TEST EXECUTION
        ///////////////////////////////////////////////////////////////

        // 1. User makes initial deposit into wrapper
        _depositIntoWrapper(rewardVault, user, initialDeposit);
        assertEq(wrapper.balanceOf(user), initialDeposit, "Initial deposit should succeed");

        // 2. Simulate rewards accumulation
        uint128 extraRewardAmount = 1e20;
        deal(Common.WETH, address(this), extraRewardAmount);
        IERC20(Common.WETH).approve(address(rewardVault), extraRewardAmount);
        rewardVault.depositRewards(Common.WETH, extraRewardAmount);

        simulateRewards(rewardVault, rewardAmount);
        deal(address(rewardToken), address(accountant), rewardAmount);
        skip(2 days);
        harvest();

        // 3. Record balances before re-deposit (don't check pending - it may be stale)
        uint256 mainTokenBalanceBefore = _balanceOf(rewardToken, user);
        uint256 extraTokenBalanceBefore = IERC20(Common.WETH).balanceOf(user);

        // 4. User makes additional deposit (this should auto-claim pending rewards)
        _depositIntoWrapper(rewardVault, user, additionalDeposit);

        // 5. Verify rewards were automatically claimed during re-deposit
        uint256 mainTokenBalanceAfter = _balanceOf(rewardToken, user);
        uint256 extraTokenBalanceAfter = IERC20(Common.WETH).balanceOf(user);

        // 6. Verify substantial amounts were claimed (not just dust)
        assertGt(mainTokenBalanceAfter, mainTokenBalanceBefore, "Main rewards should be auto-claimed");
        assertGt(extraTokenBalanceAfter, extraTokenBalanceBefore, "Extra rewards should be auto-claimed");
        assertGt(mainTokenBalanceAfter - mainTokenBalanceBefore, 1e18, "Significant main rewards claimed");
        assertGt(extraTokenBalanceAfter - extraTokenBalanceBefore, 1e16, "Significant extra rewards claimed");
    }

    // @dev Test the extra rewards distribution is fair between users (second user gets 0)
    function test_extraRewardsFairDistribution() public {
        address firstUser = makeAddr("firstUser");
        address secondUser = makeAddr("secondUser");

        (RewardVault[] memory vaults,) = deployRewardVaults();
        RewardVault rewardVault = vaults[0];

        wrapper = new StrategyWrapper(rewardVault, address(new MorphoMock()), address(this));

        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.isRegistrar.selector, address(this)),
            abi.encode(true)
        );
        rewardVault.addRewardToken(Common.WETH, address(this));

        // 1. First user deposits to the vault
        _depositIntoWrapper(rewardVault, firstUser, 1e18);

        // 2. Deposit some extra reward token into the reward vault
        uint128 extraRewardAmount = 1e20;
        deal(Common.WETH, address(this), extraRewardAmount);
        IERC20(Common.WETH).approve(address(rewardVault), extraRewardAmount);
        rewardVault.depositRewards(Common.WETH, extraRewardAmount);

        // 3. Second user deposits to the vault after 1 week
        skip(7 days);
        _depositIntoWrapper(rewardVault, secondUser, 100_000e18);

        // 4. Second user withdraws immediately after depositing
        _withdrawFromWrapper(secondUser, 100_000e18);

        // 5. First user claims extra rewards
        _claimExtraRewardsFromWrapper(firstUser);

        // The second user received nothing while the first one received all the extra reward tokens
        assertApproxEqRel(
            IERC20(Common.WETH).balanceOf(firstUser),
            extraRewardAmount,
            1e15, // 0.1% (rounding)
            "First user: should have the expected extra reward token balance"
        );
        assertApproxEqRel(
            IERC20(Common.WETH).balanceOf(secondUser),
            0,
            1e15, // 0.1% (rounding)
            "Second user: should have no extra reward token balance"
        );
    }

    function _depositIntoWrapper(RewardVault rewardVault, address account, uint256 amount) internal {
        // 1. Mint the shares token by depositing into the reward vault
        deposit(rewardVault, account, amount);

        // 2. Approve the shares token to be spent by the wrapper
        vm.startPrank(account);
        rewardVault.approve(address(wrapper), amount);

        // 3. Deposit the shares token into the wrapper
        wrapper.depositShares();
        vm.stopPrank();
    }

    function _depositIntoMorpho(address account, uint256 amount) internal {
        vm.startPrank(account);
        wrapper.approve(address(morpho), amount);
        morpho.deposit(address(wrapper), amount);
        vm.stopPrank();
    }

    function _withdrawFromMorpho(address account, uint256 amount) internal {
        vm.startPrank(account);
        morpho.withdraw(address(wrapper), amount);
        vm.stopPrank();
    }

    function _claimFromWrapper(address user) internal {
        vm.prank(user);
        wrapper.claim();
    }

    function _claimExtraRewardsFromWrapper(address user) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = Common.WETH;
        vm.prank(user);
        wrapper.claimExtraRewards(tokens);
    }

    function _withdrawFromWrapper(address user, uint256 amount) internal {
        vm.prank(user);
        wrapper.withdraw(amount, user);
    }
}

contract MorphoMock {
    mapping(address user => mapping(address asset => uint256 balance)) public balances;

    function deposit(address asset, uint256 amount) external {
        balances[msg.sender][asset] += amount;
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address asset, uint256 amount) external {
        balances[msg.sender][asset] -= amount;
        IERC20(asset).transfer(msg.sender, amount);
    }
}
