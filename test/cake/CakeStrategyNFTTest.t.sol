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

contract CakeStrategyNFTTest is Test {
    CakeStrategyNFT internal strategyImpl;
    CakeStrategyNFT internal strategy;
    Executor internal executor;

    ILocker internal constant LOCKER = ILocker(CAKE.LOCKER);
    address internal constant REWARD_TOKEN = CAKE.TOKEN;
    address internal constant MS = DAO.GOVERNANCE;

    address internal nftHolder = 0x3E61DFfa0bC323Eaa16F4C982F96FEB89ab89E8a;
    uint256 internal nftId = 382161;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("bnb"), 35_094_542);
        // Deploy Executor
        executor = new Executor(MS);
        strategyImpl = new CakeStrategyNFT(address(this), address(LOCKER), REWARD_TOKEN);
        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));
        strategy = CakeStrategyNFT(payable(strategyProxy));
        strategy.initialize(address(this), address(executor));

        vm.startPrank(MS);
        LOCKER.transferGovernance(address(executor));
        executor.execute(address(LOCKER), 0, abi.encodeWithSignature("acceptGovernance()"));
        assertEq(LOCKER.governance(), address(executor));
        executor.allowAddress(address(strategy));
        vm.stopPrank();
    }

    function test_deposit_nft() external {
        _depositNft();
    }

    function test_withdraw_nft() external {
        _depositNft();

        vm.prank(nftHolder);
        strategy.withdrawNft(nftId);
        assertEq(strategy.nftStakers(nftId), address(0));
        ICakeMc.UserPositionInfo memory userInfo = ICakeMc(strategy.cakeMc()).userPositionInfos(nftId);
        assertEq(userInfo.user, address(0));
    }

    function test_harvest_nft() external {
        _depositNft();

        skip(1 days);

        uint256 nftHolderBalance = ERC20(REWARD_TOKEN).balanceOf(nftHolder);
        vm.prank(nftHolder);
        strategy.harvestNftReward(nftId);
        // protocol fees at 0%
        assertGt(ERC20(REWARD_TOKEN).balanceOf(nftHolder) - nftHolderBalance, 0);
    }

    function test_decrease_liquidity() external {
        _depositNft();
        (,, address token0, address token1,,,, uint256 currentLiq,,, uint128 tokenOwed0, uint128 tokenOwed1) =
            ICakeNfpm(strategy.cakeNfpm()).positions(nftId);
        assertEq(tokenOwed0, 0);
        assertEq(tokenOwed1, 0);
        uint256 token0BalanceBefore = ERC20(token0).balanceOf(nftHolder);
        uint256 token1BalanceBefore = ERC20(token1).balanceOf(nftHolder);

        vm.prank(nftHolder);
        strategy.decreaseLiquidity(nftId, uint128(currentLiq / 2), 0, 0);

        (,,,,,,, uint256 newLiq,,, uint128 tokenOwed0After, uint128 tokenOwed1After) =
            ICakeNfpm(strategy.cakeNfpm()).positions(nftId);
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
        ICakeMc.UserPositionInfo memory userInfo = ICakeMc(strategy.cakeMc()).userPositionInfos(nftId);
        assertEq(userInfo.user, address(LOCKER));
    }
}
