// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "address-book/lockers/1.sol";
import {DAO} from "address-book/dao/1.sol";
import "src/yearn/depositor/YFIDepositorHelper.sol";

contract DeployYearnDepositHelper is Script {
    YFIDepositorHelper internal depositorHelper;

    address public YEARN_DEPOSITOR = 0xf908C0281f4bAfbca67e490edae816B8472608C8;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        depositorHelper = new YFIDepositorHelper(YEARN_DEPOSITOR, YFI.TOKEN);

        vm.stopBroadcast();
    }
}
