// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";
import {YearnAccumulatorV2} from "src/yearn/accumulator/YearnAccumulatorV2.sol";

contract DeployYearnAccumulatorV2 is Script, Test {
    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant YEARN_STRATEGY = 0x1be150a35bb8233d092747eBFDc75FB357c35168;
    address public constant GOV = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address public sdYfiLG;
    address public yfiLocker;

    YearnAccumulatorV2 public accumulator;

    function run() public {
        vm.startBroadcast(DEPLOYER);
        sdYfiLG = AddressBook.GAUGE_SDYFI;
        yfiLocker = AddressBook.YFI_LOCKER;
        accumulator =
            new YearnAccumulatorV2(sdYfiLG, yfiLocker, GOV, GOV, YEARN_STRATEGY, GOV);
        assertEq(accumulator.governance(), GOV);
        vm.stopBroadcast();
    }
}
