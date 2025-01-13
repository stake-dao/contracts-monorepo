// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import {BaseZeroLendLpTest} from "test/linea/zerolend/common/BaseZeroLendLpTest.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";

// end to end tests for the ZeroLend integration
contract ZeroLendLpTest is BaseZeroLendLpTest {
    constructor() {}

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("linea"), 14_369_758);
        vm.selectFork(forkId);

        _deployZeroLpIntegration();
    }

    function _depositTokens() public {
        zeroLpToken.approve(address(depositor), 1 ether);
        depositor.deposit(1 ether, true, false, address(this));
    }

    function test_canDepositTokens() public {
        assertEq(zeroLpToken.balanceOf(address(this)) > 1 ether, true);

        _depositTokens();

        // validate that sdZeroLp was minted
        assertEq(ISdToken(sdToken).balanceOf(address(this)), 1 ether);
    }

    function _claimRewards() public {
        accumulator.claimAndNotifyAll(false, false);
    }

    function test_canClaimRewards() public {
        _depositTokens();

        skip(3600 * 24 * 30);

        _claimRewards();

        assertEq(WETH.balanceOf(address(liquidityGauge)) > 0, true);

        // TODO make the math to test that the amount received by the gauge is exactly what was expected
    }

    // TODO
    // function test_canClaimRewardsFromGauge() public {}

    // TODO test with multiple stakers

    // TODO test where withdraw tokens
}
