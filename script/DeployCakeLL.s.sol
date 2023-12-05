// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {Constants} from "src/base/utils/Constants.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {CakeLocker} from "src/cake/locker/CakeLocker.sol";
import {CAKEDepositor} from "src/cake/depositor/CAKEDepositor.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

contract DeployCakeAccumulator is Script, Test {
    CakeAccumulator private accumulator;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        vm.stopBroadcast();
    }
}