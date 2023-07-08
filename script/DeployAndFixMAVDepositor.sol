// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "src/mav/locker/MAVLocker.sol";
import "src/mav/depositor/MAVDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployAndFixMAVDepositor is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    IERC20 private token = IERC20(0x7448c7456a97769F6cD04F1E83A4a23cCdC46aBD);

    address private veToken = 0x4949Ac21d5b2A0cCd303C20425eeb29DCcba66D8;
    address internal _sdToken = 0x2131197Fc08623c971916E076aF4ea3c0f42E209;
    address internal liquidityGauge = 0xdE65a189EbF9B698a935E13cD58c3E7CEABe9375;

    MAVDepositor private depositor;

    MAVLocker private locker = MAVLocker(payable(0xdBD6170396ECE3DCd51195950A2dF7F7635F9e38));
    MAVDepositor private oldDepositor = MAVDepositor(0x3Ac34fe88E434812ddC4A29Caa8234328983a13C);

    function run() public {
        vm.startBroadcast(deployer);

        depositor = new MAVDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge));
        // oldDepositor.setSdTokenMinterOperator(address(depositor));
        locker.setDepositor(address(depositor));

        if (locker.token() != address(token)) revert();
        if (locker.veToken() != address(veToken)) revert();
        if (locker.depositor() != address(depositor)) revert();
        if (locker.governance() != address(deployer)) revert();

        if (depositor.token() != address(token)) revert();
        if (depositor.locker() != address(locker)) revert();
        if (depositor.minter() != address(_sdToken)) revert();
        if (depositor.governance() != address(deployer)) revert();
        if (depositor.gauge() != address(liquidityGauge)) revert();
        if (sdToken(_sdToken).operator() != address(depositor)) revert();

        vm.stopBroadcast();
    }
}
