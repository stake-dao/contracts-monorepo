// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/utils/LibClone.sol";

import {ILocker} from "src/base/interfaces/ILocker.sol";
import {CakeStrategy} from "src/cake/strategy/CakeStrategy.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract CakeStrategyTest is Test {
    CakeStrategy public strategyImpl;
    CakeStrategy public strategy;

    ILocker public locker;
    address public veToken;
    address public rewardToken;
    address public minter;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("bnb"));
        strategyImpl = new CakeStrategy(address(this), address(locker), veToken, rewardToken, minter);
        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));
        strategy = CakeStrategy(payable(strategyProxy));
        strategy.initialize(address(this));
    }

    function test_deposit_nft() external {}

    function test_withdraw_nft() external {}

    function test_harvest_nft() external {}
}
