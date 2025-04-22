// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";

import "address-book/src/dao/56.sol";
import "address-book/src/lockers/56.sol";
import "address-book/src/protocols/56.sol";

import {ERC20} from "solady/src/tokens/ERC20.sol";
import "src/common/locker/Redeem.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {IVeANGLE} from "src/common/interfaces/IVeANGLE.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";

contract RedeemCakeTest is Test {
    using Math for uint256;

    ERC20 public token;
    ERC20 public sdToken;
    ERC20 public sdTokenGauge;
    ILiquidityGauge public gauge;

    Redeem public redeem;
    uint256 public conversionRate;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("bnb"), 48_580_933);

        token = ERC20(CAKE.TOKEN);
        sdToken = ERC20(CAKE.SDTOKEN);
        sdTokenGauge = ERC20(CAKE.GAUGE);

        conversionRate = 1e18;

        redeem = new Redeem(CAKE.TOKEN, CAKE.SDTOKEN, CAKE.GAUGE, conversionRate, 27 weeks, address(this));

        uint256 balance = sdToken.totalSupply();
        deal(CAKE.TOKEN, address(redeem), balance);

        vm.prank(CAKE.DEPOSITOR);
        ISdToken(CAKE.SDTOKEN).setOperator(address(redeem));

        /// To avoid revert when dealing with sdTokenGauge.
        deal(CAKE.TOKEN, address(sdTokenGauge), 100_000_000e18);
    }

    function test_setup() public view {
        assertGe(token.balanceOf(address(redeem)), sdToken.totalSupply());
    }

    function test_redeem_sdToken(uint256 amount) public {
        vm.assume(amount < sdToken.totalSupply());
        vm.assume(amount > 1e18);

        deal(address(sdToken), address(this), amount);

        /// 1. Approve sdToken
        sdToken.approve(address(redeem), amount);

        /// 2. Snapshot the balance of the redeem contract
        uint256 balanceBefore = token.balanceOf(address(redeem));

        /// 3. Redeem
        redeem.redeem();

        /// 4. Get the expected amount
        uint256 expected = amount.mulDiv(conversionRate, 1e18);

        /// 5. Assert
        assertEq(token.balanceOf(address(redeem)), balanceBefore - expected);
        assertEq(token.balanceOf(address(this)), expected);
    }

    function test_redeem_sdTokenGauge(uint256 amount) public {
        vm.assume(amount < sdTokenGauge.totalSupply());
        vm.assume(amount > 1e18);

        deal(address(sdTokenGauge), address(this), amount);

        /// 3. Approve sdTokenGauge
        sdTokenGauge.approve(address(redeem), amount);

        /// 4. Snapshot the balance of the redeem contract
        uint256 balanceBefore = token.balanceOf(address(redeem));

        uint256 claimable = ILiquidityGauge(CAKE.GAUGE).claimable_reward(address(this), CAKE.TOKEN);

        /// 5. Redeem
        redeem.redeem();

        /// 7. Get the expected amount
        uint256 expected = amount.mulDiv(conversionRate, 1e18);

        /// 8. Assert
        assertEq(token.balanceOf(address(redeem)), balanceBefore - expected);
        assertEq(token.balanceOf(address(this)), expected + claimable);
    }

    function test_redeem_withAllTokens(uint256 amount) public {
        vm.assume(amount < sdToken.totalSupply());
        vm.assume(amount > 1e18);

        uint256 sdTokenBalance = amount / 2;
        uint256 sdTokenGaugeBalance = amount - sdTokenBalance;

        deal(address(sdToken), address(this), sdTokenBalance);
        deal(address(sdTokenGauge), address(this), sdTokenGaugeBalance);

        /// 1. Approve sdToken
        sdToken.approve(address(redeem), sdTokenBalance);

        /// 2. Approve sdTokenGauge
        sdTokenGauge.approve(address(redeem), sdTokenGaugeBalance);

        uint256 claimable = ILiquidityGauge(CAKE.GAUGE).claimable_reward(address(this), CAKE.TOKEN);

        /// 3. Snapshot the balance of the redeem contract
        uint256 balanceBefore = token.balanceOf(address(redeem));

        /// 3. Redeem
        redeem.redeem();

        /// 4. Get the expected amount
        uint256 expected = amount.mulDiv(conversionRate, 1e18);

        /// 5. Assert
        assertEq(token.balanceOf(address(redeem)), balanceBefore - expected);
        assertEq(token.balanceOf(address(this)), expected + claimable);

        /// 6. Assert that the redeem is not finalized
        vm.expectRevert(Redeem.RedeemCooldown.selector);
        redeem.retrieve();

        skip(27 weeks);

        uint256 balanceBeforeRetrieve = token.balanceOf(address(this));
        uint256 balanceBeforeRedeem = token.balanceOf(address(redeem));

        redeem.retrieve();

        assertEq(token.balanceOf(address(this)), balanceBeforeRetrieve + balanceBeforeRedeem);
    }
}
