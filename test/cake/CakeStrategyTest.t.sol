// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/utils/LibClone.sol";

import {ERC721} from "solady/tokens/ERC721.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ICakeMc} from "src/base/interfaces/ICakeMc.sol";
import {CakeStrategy} from "src/cake/strategy/CakeStrategy.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {CAKE} from "address-book/lockers/56.sol";
import {DAO} from "address-book/dao/56.sol";

contract CakeStrategyTest is Test {
    CakeStrategy internal strategyImpl;
    CakeStrategy internal strategy;

    ILocker internal constant LOCKER = ILocker(CAKE.LOCKER);
    address internal constant VE_TOKEN = address(0);
    address internal constant REWARD_TOKEN = CAKE.TOKEN;
    address internal constant MINTER = address(0);

    address internal constant MS = DAO.GOVERNANCE;

    address internal nftHolder = 0x3E61DFfa0bC323Eaa16F4C982F96FEB89ab89E8a;
    uint256 internal nftId = 382161;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("bnb"), 35_094_542);
        strategyImpl = new CakeStrategy(address(this), address(LOCKER), VE_TOKEN, REWARD_TOKEN, MINTER);
        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));
        strategy = CakeStrategy(payable(strategyProxy));
        strategy.initialize(address(this));

        vm.prank(MS);
        LOCKER.transferGovernance(address(strategy));
        strategy.execute(address(LOCKER), 0, abi.encodeWithSignature("acceptGovernance()"));
        assertEq(LOCKER.governance(), address(strategy));
    }

    function test_deposit_withdraw_nft() external {
        // send the NFT to the strategy contract
        vm.startPrank(nftHolder);
        ERC721(strategy.cakeNfpm()).safeTransferFrom(nftHolder, address(strategy), nftId);
        vm.stopPrank();
        assertEq(nftHolder, strategy.nftStakers(nftId));
        // check on cake mc
        ICakeMc.UserPositionInfo memory userInfo = ICakeMc(strategy.cakeMc()).userPositionInfos(nftId);
        assertEq(userInfo.user, address(LOCKER));

        vm.prank(nftHolder);
        strategy.withdrawNft(nftId);
        assertEq(strategy.nftStakers(nftId), address(0));
        userInfo = ICakeMc(strategy.cakeMc()).userPositionInfos(nftId);
        assertEq(userInfo.user, address(0));
    }

    function test_harvest_nft() external {}
}
