// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "src/base/interfaces/IDepositor.sol";
import "src/yearn/depositor/YFIDepositor.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";

contract DeployYFIDepositor is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address private token = AddressBook.YFI;
    address internal sdToken = AddressBook.SD_YFI;
    address private locker = AddressBook.YFI_LOCKER;
    address internal liquidityGauge = AddressBook.GAUGE_SDYFI;

    YFIDepositor private depositor;

    function run() public {
        vm.startBroadcast(deployer);

        depositor = new YFIDepositor(address(token), address(locker), address(sdToken), address(liquidityGauge));

        /// With governance, set the depositor in the locker,
        /// And change the minter.

        depositor.transferGovernance(governance);

        vm.stopBroadcast();
    }
}
