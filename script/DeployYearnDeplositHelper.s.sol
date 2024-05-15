// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "address-book/lockers/1.sol";
import {DAO} from "address-book/dao/1.sol";
import "src/yearn/depositor/YFIDepositorHelper.sol";

contract DeployYearnDepositHelper is Script {
    YFIDepositorHelper internal depositorHelper;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        depositorHelper = new YFIDepositorHelper(YFI.DEPOSITOR, YFI.TOKEN);

        vm.stopBroadcast();
    }
}
