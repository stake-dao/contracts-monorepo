// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import {ERC20} from "solady/src/tokens/ERC20.sol";
import "src/common/locker/Redeem.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {IVeANGLE} from "src/common/interfaces/IVeANGLE.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";

contract RedeemAngleTest is Test {
    using Math for uint256;

    ERC20 public token;
    ERC20 public sdToken;
    ERC20 public sdTokenGauge;
    ILiquidityGauge public gauge;

    Redeem public redeem;
    uint256 public conversionRate;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 22_168_158);

        token = ERC20(ANGLE.TOKEN);
        sdToken = ERC20(ANGLE.SDTOKEN);
        sdTokenGauge = ERC20(ANGLE.GAUGE);

        vm.prank(ANGLE.LOCKER);
        IVeANGLE(Angle.VEANGLE).withdraw_fast();

        /// @notice The conversion rate is 0.922165662297322400 ANGLE per 1e18 SDANGLE.
        /// Defined here https://gov.stakedao.org/t/sdgp-50-angle-redemption-proposal/1043
        conversionRate = 922165662297322400;

        redeem = new Redeem(ANGLE.TOKEN, ANGLE.SDTOKEN, ANGLE.GAUGE, conversionRate, address(this));

        uint256 balance = token.balanceOf(ANGLE.LOCKER);

        vm.prank(ANGLE.LOCKER);
        token.transfer(address(redeem), balance);

        vm.prank(ANGLE.DEPOSITOR);
        ISdToken(ANGLE.SDTOKEN).setOperator(address(redeem));

        /// These tokens are lost as there's no way to claim them.
        /// This is due to the fact that when Angle deprecated veANGLE, lockToken reverted, but sdAngle mint was still possible
        /// if you deposit with lock = false.
        balance = token.balanceOf(ANGLE.DEPOSITOR);

        vm.prank(ANGLE.DEPOSITOR);
        token.transfer(address(redeem), balance);

        /// To avoid revert when dealing with sdTokenGauge.
        deal(Angle.EURA, address(sdTokenGauge), 100_000_000e18);
        deal(ANGLE.TOKEN, address(sdTokenGauge), 100_000_000e18);
        deal(Angle.SAN_USDC_EUR, address(sdTokenGauge), 100_000_000e18);
    }

    function test_setup() public view {
        assertEq(token.balanceOf(ANGLE.LOCKER), 0);
        assertEq(token.balanceOf(ANGLE.DEPOSITOR), 0);
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

        uint256 claimable = ILiquidityGauge(ANGLE.GAUGE).claimable_reward(address(this), ANGLE.TOKEN);

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

        uint256 claimable = ILiquidityGauge(ANGLE.GAUGE).claimable_reward(address(this), ANGLE.TOKEN);

        /// 3. Snapshot the balance of the redeem contract
        uint256 balanceBefore = token.balanceOf(address(redeem));

        /// 3. Redeem
        redeem.redeem();

        /// 4. Get the expected amount
        uint256 expected = amount.mulDiv(conversionRate, 1e18);

        /// 5. Assert
        assertEq(token.balanceOf(address(redeem)), balanceBefore - expected);
        assertEq(token.balanceOf(address(this)), expected + claimable);
    }
}
