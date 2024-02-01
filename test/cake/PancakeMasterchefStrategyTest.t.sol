// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "solady/utils/LibClone.sol";
import "src/cake/strategy/PancakeMasterchefStrategy.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ICakeMc} from "src/base/interfaces/ICakeMc.sol";
import {Executor} from "src/cake/utils/Executor.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {DAO} from "address-book/dao/56.sol";
import {CAKE} from "address-book/lockers/56.sol";

interface ICakeV3Pool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external;
    function feeGrowthGlobal0X128() external view returns (uint256);
    function feeGrowthGlobal1X128() external view returns (uint256);
}

contract PancakeMasterchefStrategyTest is Test {
    bytes32 internal constant _ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    PancakeMasterchefStrategy internal strategyImpl;
    PancakeMasterchefStrategy internal strategy;
    Executor internal executor;

    ILocker internal constant LOCKER = ILocker(CAKE.LOCKER);
    address internal constant REWARD_TOKEN = CAKE.TOKEN;
    address internal constant MS = DAO.GOVERNANCE;

    address internal nftHolder = 0x3E61DFfa0bC323Eaa16F4C982F96FEB89ab89E8a;
    uint256 internal nftId = 382161;
    uint256[] internal nftIds = [nftId];

    address internal v3Pool = 0x7f51c8AaA6B0599aBd16674e2b17FEc7a9f674A1;

    address internal rewardRecipient = address(0xFEAB);
    address internal nftRecipient = address(0xFAEB);
    address internal rewardClaimer = address(0xFAAA);
    address internal feeReceiver = address(0xFABA);

    ICakeMc internal cakeMc;

    address internal token0;
    address internal token1;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("bnb"), 35_094_542);
        // Deploy Executor
        executor = new Executor(MS);
        strategyImpl = new PancakeMasterchefStrategy(address(this), address(LOCKER), REWARD_TOKEN);
        address strategyProxy = address(new ERC1967Proxy(address(strategyImpl), ""));
        strategy = PancakeMasterchefStrategy(payable(strategyProxy));
        strategy.initialize(address(this), address(executor));
        strategy.setRewardClaimer(rewardClaimer);
        strategy.setFeeReceiver(feeReceiver);
        cakeMc = ICakeMc(strategy.masterchef());

        vm.startPrank(MS);
        LOCKER.transferGovernance(address(executor));
        executor.execute(address(LOCKER), 0, abi.encodeWithSignature("acceptGovernance()"));
        assertEq(LOCKER.governance(), address(executor));
        executor.allowAddress(address(strategy));
        vm.stopPrank();

        (,, token0, token1,,,,,,,,) = ICakeNfpm(strategy.nonFungiblePositionManager()).positions(nftId);
        deal(token0, address(this), 1000e18);
        deal(token1, address(this), 1000e18);

        //deal(token0, nftRecipient, 10e18);
    }

    function test_deposit_nft() external {
        _depositNft();
    }

    function test_withdraw_nft() external {
        _depositNft();
        skip(1 minutes);
        _withdrawNft();
    }

    function test_withdraw_nft_recipient() external {
        _depositNft();
        skip(1 minutes);
        _withdrawNftRecipient(nftRecipient);
    }

    function test_withdraw_nft_not_staker() external {
        _depositNft();
        vm.expectRevert(PancakeMasterchefStrategy.Unauthorized.selector);
        strategy.withdraw(nftId);
    }

    function test_harvest_rewards_claimer() external {
        _depositNft();

        skip(1 days);

        uint256 nftHolderBalance = ERC20(REWARD_TOKEN).balanceOf(nftHolder);
        vm.prank(rewardClaimer);
        strategy.harvestRewards(nftIds, nftHolder);
        // protocol fees at 0%
        assertGt(ERC20(REWARD_TOKEN).balanceOf(nftHolder) - nftHolderBalance, 0);
    }

    function test_harvestNotOwner() public {
        _depositNft();

        skip(1 days);

        vm.prank(address(0xCAFE));
        vm.expectRevert(PancakeMasterchefStrategy.Unauthorized.selector);
        strategy.harvestRewards(nftIds, nftHolder);
    }

    function test_harvest_reward_protocol_fee() external {
        //set fee
        strategy.updateProtocolFee(1_500); // 15%
        _depositNft();

        skip(1 days);

        vm.prank(nftHolder);
        uint256[] memory rewards = strategy.harvestRewards(nftIds, nftHolder);
        uint256 _balanceOf = ERC20(REWARD_TOKEN).balanceOf(nftHolder);

        assertGt(rewards[0], 0);
        assertEq(rewards[0], _balanceOf);

        uint256 feeAccrued = strategy.feesAccrued();
        assertGt(feeAccrued, 0);

        uint256 feeReceiverBalance = ERC20(REWARD_TOKEN).balanceOf(feeReceiver);
        strategy.claimProtocolFees();

        uint256 feeReceiverEarned = ERC20(REWARD_TOKEN).balanceOf(feeReceiver) - feeReceiverBalance;

        assertEq(feeReceiverEarned, feeAccrued);
        assertEq(strategy.feesAccrued(), 0);
    }

    function test_harvest_reward_on_withdraw() external {
        _depositNft();

        skip(1 days);

        uint256 stakerBalance = ERC20(REWARD_TOKEN).balanceOf(nftHolder);
        _withdrawNft();
        // reward sent to the staker within the withdraw function
        assertGt(ERC20(REWARD_TOKEN).balanceOf(nftHolder) - stakerBalance, 0);
    }

    function test_collect_fee() external {
        _depositNft();

        uint256 feeGlobalBeforeSwap = ICakeV3Pool(v3Pool).feeGrowthGlobal0X128();

        ERC20(token0).approve(v3Pool, 1000e18);
        // Swap 1K token0 to token1 to increase global fees
        ICakeV3Pool(v3Pool).swap(address(this), true, 1000e18, 4295128740, "");

        uint256 feeGlobalAfterSwap = ICakeV3Pool(v3Pool).feeGrowthGlobal1X128();
        assertGt(feeGlobalAfterSwap, feeGlobalBeforeSwap);

        // collect fee
        vm.prank(nftHolder);
        PancakeMasterchefStrategy.CollectedFees[] memory fees = strategy.collectFees(nftIds, nftHolder);
        uint256 token0Collected = fees[0].token0Amount;

        assertGt(token0Collected, 0);

        uint256 _balanceOfToken0 = ERC20(token0).balanceOf(nftHolder);
        assertEq(token0Collected, _balanceOfToken0);
    }

    function test_collect_no_fee() external {
        _depositNft();

        vm.prank(nftHolder);
        vm.recordLogs();
        strategy.collectFees(nftIds, nftHolder);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // check event data
        assertEq(entries[3].topics[0], keccak256("FeeCollected(address,address,uint256,uint256)"));
        (uint256 token0Amount, uint256 token1Amount) = abi.decode(entries[3].data, (uint256, uint256));
        assertEq(token0Amount, 0);
        assertEq(token1Amount, 0);
    }

    function test_increase_liquidity() external {
        uint256 token0ToIncrease = 1e18;
        uint256 token1ToIncrease = 1e18;
        _depositNft();
        (,,,,,,, uint256 currentLiq,,,,) = ICakeNfpm(strategy.nonFungiblePositionManager()).positions(nftId);
        ERC20(token0).approve(address(cakeMc), token0ToIncrease);
        ERC20(token1).approve(address(cakeMc), token1ToIncrease);

        ICakeNfpm.IncreaseLiquidityParams memory params = ICakeNfpm.IncreaseLiquidityParams({
            tokenId: nftId,
            amount0Desired: token0ToIncrease,
            amount1Desired: token1ToIncrease,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 1 hours
        });

        cakeMc.increaseLiquidity(params);
        (,,,,,,, uint256 newLiq,,,,) = ICakeNfpm(strategy.nonFungiblePositionManager()).positions(nftId);
        assertGt(newLiq, currentLiq);
    }

    function test_decrease_liquidity() external {
        _depositNft();
        (,,,,,,, uint256 currentLiq,,, uint128 tokenOwed0, uint128 tokenOwed1) =
            ICakeNfpm(strategy.nonFungiblePositionManager()).positions(nftId);
        assertEq(tokenOwed0, 0);
        assertEq(tokenOwed1, 0);
        uint256 token0BalanceBefore = ERC20(token0).balanceOf(nftHolder);
        uint256 token1BalanceBefore = ERC20(token1).balanceOf(nftHolder);

        vm.prank(nftHolder);
        strategy.decreaseLiquidity(nftId, uint128(currentLiq / 2), 0, 0, block.timestamp + 10);

        (,,,,,,, uint256 newLiq,,, uint128 tokenOwed0After, uint128 tokenOwed1After) =
            ICakeNfpm(strategy.nonFungiblePositionManager()).positions(nftId);
        assertGt(currentLiq, newLiq);
        // collected all liquidity removed
        assertEq(tokenOwed0After, 0);
        assertEq(tokenOwed1After, 0);
        // check if the recipient received the tokens
        assertGt(ERC20(token0).balanceOf(nftHolder) - token0BalanceBefore, 0);
        assertGt(ERC20(token1).balanceOf(nftHolder) - token1BalanceBefore, 0);
    }

    function _depositNft() internal {
        // transfer the NFT to the strategy contract
        vm.startPrank(nftHolder);
        ERC721(strategy.nonFungiblePositionManager()).safeTransferFrom(nftHolder, address(strategy), nftId);
        vm.stopPrank();
        assertEq(nftHolder, strategy.positionOwner(nftId));
        // check on cake mc
        ICakeMc.UserPositionInfo memory userInfo = cakeMc.userPositionInfos(nftId);
        assertEq(userInfo.user, address(LOCKER));
    }

    function _withdrawNft() internal {
        vm.prank(nftHolder);
        strategy.withdraw(nftId);
        assertEq(strategy.positionOwner(nftId), address(0));
        ICakeMc.UserPositionInfo memory userInfo = cakeMc.userPositionInfos(nftId);
        assertEq(userInfo.user, address(0));
        // check NFT recevied by the staker
        assertEq(ERC721(strategy.nonFungiblePositionManager()).ownerOf(nftId), nftHolder);
    }

    function _withdrawNftRecipient(address _recipient) internal {
        vm.prank(nftHolder);
        strategy.withdraw(nftId, _recipient);
        assertEq(strategy.positionOwner(nftId), address(0));
        ICakeMc.UserPositionInfo memory userInfo = cakeMc.userPositionInfos(nftId);
        assertEq(userInfo.user, address(0));
        // check NFT received by the recipient
        assertEq(ERC721(strategy.nonFungiblePositionManager()).ownerOf(nftId), _recipient);
    }

    function pancakeV3SwapCallback(int256 _amount0, int256 _amount1, bytes calldata) external {
        if (_amount0 > 0) {
            ERC20(token0).transfer(msg.sender, uint256(_amount0));
        }
        if (_amount1 > 0) {
            ERC20(token1).transfer(msg.sender, uint256(_amount1));
        }
    }

    function test_InitializeTwice() public {
        vm.expectRevert(PancakeMasterchefStrategy.AddressNull.selector);
        strategy.initialize(address(0xCAFE), address(0xCAFE));

        vm.expectRevert(PancakeMasterchefStrategy.AddressNull.selector);
        strategyImpl.initialize(address(0xCAFE), address(0xCAFE));
    }

    function test_NotDelegatedGuard() public {
        assertEq(strategyImpl.proxiableUUID(), _ERC1967_IMPLEMENTATION_SLOT);

        vm.expectRevert(UUPSUpgradeable.UnauthorizedCallContext.selector);
        strategy.proxiableUUID();
    }

    function test_OnlyProxyGuard() public {
        vm.expectRevert(UUPSUpgradeable.UnauthorizedCallContext.selector);
        strategyImpl.upgradeToAndCall(address(1), "");
    }

    function test_UpgradeToWrongCaller() public {
        vm.prank(address(0xCAFE));
        vm.expectRevert(PancakeMasterchefStrategy.Unauthorized.selector);
        strategy.upgradeToAndCall(address(1), "");
    }

    function test_updateGovernanceAndUpdate() public {
        PancakeMasterchefStrategy impl2 = new PancakeMasterchefStrategy(address(this), address(LOCKER), REWARD_TOKEN);

        strategy.transferGovernance(address(0xCAFE));

        address _executor = address(strategy.executor());

        vm.prank(address(0xCAFE));
        strategy.acceptGovernance();

        assertEq(strategy.governance(), address(0xCAFE));

        vm.expectRevert(PancakeMasterchefStrategy.Unauthorized.selector);
        strategy.upgradeToAndCall(address(impl2), "");

        vm.prank(address(0xCAFE));
        strategy.upgradeToAndCall(address(impl2), "");

        bytes32 v = vm.load(address(strategy), _ERC1967_IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(v))), address(impl2));

        assertEq(strategy.governance(), address(0xCAFE));
        assertEq(address(strategy.executor()), _executor);

        vm.expectRevert(PancakeMasterchefStrategy.AddressNull.selector);
        strategy.initialize(address(0xCAFE), address(0xCAFE));

        vm.expectRevert(PancakeMasterchefStrategy.AddressNull.selector);
        impl2.initialize(address(0xCAFE), address(0xCAFE));
    }

    event Upgraded(address indexed implementation);

    function test_UpgradeTo() public {
        PancakeMasterchefStrategy impl2 = new PancakeMasterchefStrategy(address(this), address(LOCKER), REWARD_TOKEN);

        vm.expectEmit(true, true, true, true);

        emit Upgraded(address(impl2));
        strategy.upgradeToAndCall(address(impl2), "");

        bytes32 v = vm.load(address(strategy), _ERC1967_IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(v))), address(impl2));
    }
}
