// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import {ERC20} from "solady/src/tokens/ERC20.sol";

import {Redeem} from "src/mainnet/fpis/Redeem.sol";
import {IVeFPIS} from "src/common/interfaces/IVeFPIS.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";

contract RedeemTest is Test {
    ERC20 public token;
    ERC20 public sdToken;
    ERC20 public sdTokenGauge;
    ILiquidityGauge public gauge;
    Redeem redeem;

    address[] holders = [
        0xb0e83C2D71A991017e0116d58c5765Abc57384af,
        0x656e1A01055566ad6A06830Add7a0F5EF7dd2512,
        0x55A183e160F8903766E2Dd53F3580C7049b1b2Dc,
        0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063,
        0xf23E1bEFC889Ac30991762eD44fbD8EBF260419b,
        0x074c3dE651d6EcDbf79164AB8392eD388aAcCb04,
        0x58E03d622a88b4012ee0a97235C6b110077FB867,
        0x520bac9FD09D10BD4eA44f120f283354D2077fd3,
        0x499487f6BE895B71cF57881c22D5f6D855fCB8A2,
        0x6Ab92DF64Db6C648e5c634062bfb8627783fb3d9,
        0x7e1E1c5ac70038a9718431C92A618F01f8DADa18,
        0x06c21B5d004604250a7f9639c4A3C28e73742261,
        0xb957DccaA1CCFB1eB78B495B499801D591d8a403,
        0x16C6521Dff6baB339122a0FE25a9116693265353
    ];

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21831769);

        token = ERC20(FPIS.TOKEN);
        sdToken = ERC20(FPIS.SDTOKEN);
        sdTokenGauge = ERC20(FPIS.GAUGE);
        gauge = ILiquidityGauge(FPIS.GAUGE);

        vm.prank(FPIS.LOCKER);
        IVeFPIS(Frax.VEFPIS).withdraw();

        redeem = new Redeem(FPIS.TOKEN, FPIS.SDTOKEN, FPIS.GAUGE);

        vm.startPrank(FPIS.LOCKER);
        token.transfer(address(redeem), token.balanceOf(FPIS.LOCKER));
        vm.stopPrank();

        vm.prank(ISdToken(FPIS.SDTOKEN).burner());
        ISdToken(FPIS.SDTOKEN).setBurnerOperator(address(redeem));
    }

    function test_initialState() public view {
        assertEq(token.balanceOf(address(redeem)), sdToken.totalSupply());
    }

    function test_redeem() public {
        // TODO: legacy governance address -- This test must be rewritten ASAP
        address governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
        uint256 initialTokenBalance = token.balanceOf(governance);
        uint256 sdTokenBalance = sdToken.balanceOf(governance);
        uint256 sdTokenGaugeBalance = sdTokenGauge.balanceOf(governance);
        uint256 initialTokenSupply = sdToken.totalSupply();
        uint256 claimableFromGauge = gauge.claimable_reward(governance, FPIS.TOKEN);

        vm.startPrank(governance);
        sdToken.approve(address(redeem), sdTokenBalance);
        sdTokenGauge.approve(address(redeem), sdTokenGaugeBalance);
        redeem.redeem();
        vm.stopPrank();

        uint256 expectedBalance = sdTokenGaugeBalance > 0
            ? sdTokenBalance + sdTokenGaugeBalance + claimableFromGauge + initialTokenBalance
            : sdTokenBalance + initialTokenBalance;

        assertEq(token.balanceOf(governance), expectedBalance);
        assertEq(initialTokenSupply - (sdTokenBalance + sdTokenGaugeBalance), sdToken.totalSupply());
        assertEq(token.balanceOf(address(redeem)), sdToken.totalSupply());
        assertEq(sdToken.balanceOf(governance), 0);
        assertEq(sdTokenGauge.balanceOf(governance), 0);
    }

    function test_redeemAll() public {
        for (uint256 i = 0; i < holders.length; i++) {
            uint256 initialTokenBalance = token.balanceOf(holders[i]);
            uint256 sdTokenBalance = sdToken.balanceOf(holders[i]);
            uint256 sdTokenGaugeBalance = sdTokenGauge.balanceOf(holders[i]);
            uint256 claimableFromGauge = gauge.claimable_reward(holders[i], FPIS.TOKEN);

            vm.startPrank(holders[i]);
            sdToken.approve(address(redeem), sdTokenBalance);
            sdTokenGauge.approve(address(redeem), sdTokenGaugeBalance);
            redeem.redeem();
            vm.stopPrank();

            uint256 expectedBalance = sdTokenGaugeBalance > 0
                ? sdTokenBalance + sdTokenGaugeBalance + claimableFromGauge + initialTokenBalance
                : sdTokenBalance + initialTokenBalance;

            assertEq(token.balanceOf(holders[i]), expectedBalance);
            assertEq(token.balanceOf(address(redeem)), sdToken.totalSupply());
            assertEq(sdToken.balanceOf(holders[i]), 0);
            assertEq(sdTokenGauge.balanceOf(holders[i]), 0);
        }

        assertEq(sdToken.totalSupply(), 0);
        assertEq(token.balanceOf(address(redeem)), 0);
    }
}
