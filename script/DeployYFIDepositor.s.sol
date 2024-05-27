// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";

import "src/yearn/depositor/YFIDepositorV2.sol";
import {FXNAccumulator} from "src/fx/accumulator/FXNAccumulator.sol";

contract DeployYFIDepositor is Script {
    FXNAccumulator public accumulator;

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address internal constant POOL = 0x852b90239C5034b5bb7a5e54eF1bEF3Ce3359CC8;

    YFIDepositorV2 private depositor;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        depositor =
            new YFIDepositorV2(address(YFI.TOKEN), address(YFI.LOCKER), address(YFI.SDTOKEN), address(YFI.GAUGE), POOL);
        depositor.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
