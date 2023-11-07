// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "src/mav/locker/MAVLocker.sol";
import "src/mav/depositor/MAVDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpdateSDMavOperation is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    sdToken internal _sdToken;
    MAVDepositor private depositor;

    function run() public {
        vm.startBroadcast(deployer);

        _sdToken = sdToken(payable(0x50687515e93C43964733282F9DB8683F80BB02f9));
        depositor = MAVDepositor(0x177Eaa1A7c26da6Dc84c0cC3F9AE6Fd0A470E7Ec);

        _sdToken.setOperator(address(depositor));

        vm.stopBroadcast();
    }
}
