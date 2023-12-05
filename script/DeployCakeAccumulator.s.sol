// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {CakeAccumulator} from "src/cake/accumulator/CakeAccumulator.sol";

contract DeployCakeAccumulator is Script {
    CakeAccumulator public accumulator;

    address[] public revenueSharingPools = [
        0xCaF4e48a4Cb930060D0c3409F40Ae7b34d2AbE2D, // revenue share
        0x9cac9745731d1Cf2B483f257745A512f0938DD01 // veCAKe emission
    ];

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;

    address public constant CAKE = AddressBook.CAKE;
    address public constant CAKE_LOCKER = AddressBook.CAKE_LOCKER;
    address public constant SD_CAKE_GAUGE = AddressBook.GAUGE_SDCAKE;
    address public constant RSPG = 0x011f2a82846a4E9c62C2FC4Fd6fDbad19147D94A;
    address public constant EXTRA_REWARD = 0x4DB5a66E937A9F4473fA95b1cAF1d1E1D62E29EA;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        accumulator = new CakeAccumulator(SD_CAKE_GAUGE, CAKE_LOCKER, GOVERNANCE, GOVERNANCE, GOVERNANCE);

        vm.stopBroadcast();
    }
}
