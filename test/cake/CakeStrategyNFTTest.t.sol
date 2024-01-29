// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/utils/LibClone.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ICakeMc} from "src/base/interfaces/ICakeMc.sol";
import {ICakeNfpm} from "src/base/interfaces/ICakeNfpm.sol";
import {CakeStrategyNFT} from "src/cake/strategy/CakeStrategyNFT.sol";
import {Executor} from "src/cake/utils/Executor.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {CAKE} from "address-book/lockers/56.sol";
import {DAO} from "address-book/dao/56.sol";

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

contract CakeStrategyNFTTest is Test {
    CakeStrategyNFT internal strategyImpl;
    CakeStrategyNFT internal strategy;
    Executor internal executor;

    ILocker internal constant LOCKER = ILocker(CAKE.LOCKER);
    address internal constant REWARD_TOKEN = CAKE.TOKEN;
    address internal constant MS = DAO.GOVERNANCE;

    address internal nftHolder = 0x3E61DFfa0bC323Eaa16F4C982F96FEB89ab89E8a;
    uint256 internal nftId = 382161;
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
        strategyImpl = new CakeStrategyNFT(address(this), address(LOCKER), REWARD_TOKEN);
        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));
        strategy = CakeStrategyNFT(payable(strategyProxy));
        strategy.initialize(address(this), address(executor));
        strategy.setRewardClaimer(rewardClaimer);
        strategy.setFeeReceiver(feeReceiver);
        cakeMc = ICakeMc(strategy.cakeMc());

        vm.startPrank(MS);
        LOCKER.transferGovernance(address(executor));
        executor.execute(address(LOCKER), 0, abi.encodeWithSignature("acceptGovernance()"));
        assertEq(LOCKER.governance(), address(executor));
        executor.allowAddress(address(strategy));
        vm.stopPrank();

        (,, token0, token1,,,,,,,,) = ICakeNfpm(strategy.cakeNfpm()).positions(nftId);
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
        vm.expectRevert(CakeStrategyNFT.Unauthorized.selector);
        strategy.withdrawNft(nftId);
    }

    function test_harvest_reward() external {
        _depositNft();

        skip(1 days);

        uint256 nftHolderBalance = ERC20(REWARD_TOKEN).balanceOf(nftHolder);
        vm.prank(nftHolder);
        strategy.harvestReward(nftId, nftHolder);
        // protocol fees at 0%
        assertGt(ERC20(REWARD_TOKEN).balanceOf(nftHolder) - nftHolderBalance, 0);
    }

    function test_harvest_rewards_claimer() external {
        _depositNft();

        skip(1 days);

        uint256[] memory nftIds = new uint256[](1);
        nftIds[0] = nftId;
        uint256 nftHolderBalance = ERC20(REWARD_TOKEN).balanceOf(nftHolder);
        vm.prank(rewardClaimer);
        strategy.harvestRewards(nftIds, nftHolder);
        // protocol fees at 0%
        assertGt(ERC20(REWARD_TOKEN).balanceOf(nftHolder) - nftHolderBalance, 0);
    }

    function test_harvest_reward_protocol_fee() external {
        //set fee
        strategy.updateProtocolFee(1_500); // 15%
        _depositNft();

        skip(1 days);

        uint256 nftHolderBalance = ERC20(REWARD_TOKEN).balanceOf(nftHolder);
        vm.prank(nftHolder);
        strategy.harvestReward(nftId, nftHolder);

        assertGt(ERC20(REWARD_TOKEN).balanceOf(nftHolder) - nftHolderBalance, 0);
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
        uint256 token0Before = ERC20(token0).balanceOf(nftHolder);
        vm.prank(nftHolder);
        strategy.collectFee(nftId, nftHolder);
        uint256 token0Collected = ERC20(token0).balanceOf(nftHolder) - token0Before;
        assertGt(token0Collected, 0);
    }

    function test_collect_no_fee() external {
        _depositNft();

        vm.prank(nftHolder);
        vm.recordLogs();
        strategy.collectFee(nftId, nftHolder);
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
        (,,,,,,, uint256 currentLiq,,,,) = ICakeNfpm(strategy.cakeNfpm()).positions(nftId);
        ERC20(token0).approve(address(strategy), token0ToIncrease);
        ERC20(token1).approve(address(strategy), token1ToIncrease);
        strategy.increaseLiquidity(nftId, token0ToIncrease, token1ToIncrease, 0, 0);
        (,,,,,,, uint256 newLiq,,,,) = ICakeNfpm(strategy.cakeNfpm()).positions(nftId);
        assertGt(newLiq, currentLiq);
    }

    function test_decrease_liquidity() external {
        _depositNft();
        (,,,,,,, uint256 currentLiq,,, uint128 tokenOwed0, uint128 tokenOwed1) =
            ICakeNfpm(strategy.cakeNfpm()).positions(nftId);
        assertEq(tokenOwed0, 0);
        assertEq(tokenOwed1, 0);
        uint256 token0BalanceBefore = ERC20(token0).balanceOf(nftHolder);
        uint256 token1BalanceBefore = ERC20(token1).balanceOf(nftHolder);

        vm.prank(nftHolder);
        strategy.decreaseLiquidity(nftId, uint128(currentLiq / 2), 0, 0);

        (,,,,,,, uint256 newLiq,,, uint128 tokenOwed0After, uint128 tokenOwed1After) =
            ICakeNfpm(strategy.cakeNfpm()).positions(nftId);
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
        ERC721(strategy.cakeNfpm()).safeTransferFrom(nftHolder, address(strategy), nftId);
        vm.stopPrank();
        assertEq(nftHolder, strategy.nftStakers(nftId));
        // check on cake mc
        ICakeMc.UserPositionInfo memory userInfo = cakeMc.userPositionInfos(nftId);
        assertEq(userInfo.user, address(LOCKER));
    }

    function _withdrawNft() internal {
        vm.prank(nftHolder);
        strategy.withdrawNft(nftId);
        assertEq(strategy.nftStakers(nftId), address(0));
        ICakeMc.UserPositionInfo memory userInfo = cakeMc.userPositionInfos(nftId);
        assertEq(userInfo.user, address(0));
        // check NFT recevied by the staker
        assertEq(ERC721(strategy.cakeNfpm()).ownerOf(nftId), nftHolder);
    }

    function _withdrawNftRecipient(address _recipient) internal {
        vm.prank(nftHolder);
        strategy.withdrawNft(nftId, _recipient);
        assertEq(strategy.nftStakers(nftId), address(0));
        ICakeMc.UserPositionInfo memory userInfo = cakeMc.userPositionInfos(nftId);
        assertEq(userInfo.user, address(0));
        // check NFT received by the recipient
        assertEq(ERC721(strategy.cakeNfpm()).ownerOf(nftId), _recipient);
    }

    function pancakeV3SwapCallback(int256 _amount0, int256 _amount1, bytes calldata) external {
        if (_amount0 > 0) {
            ERC20(token0).transfer(msg.sender, uint256(_amount0));
        }
        if (_amount1 > 0) {
            ERC20(token1).transfer(msg.sender, uint256(_amount1));
        }
    }
}
