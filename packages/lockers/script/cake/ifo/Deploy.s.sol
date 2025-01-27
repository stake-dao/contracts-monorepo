// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/42161.sol";
import "address-book/src/lockers/42161.sol";

import "src/arbitrum/cake/IFOFactory.sol";
import "src/arbitrum/cake/IFOHelper.sol";

contract Deploy is Script {
    address public constant CAKE_IFO = 0xa6f907493269BEF3383fF0CBFd25e1Cc35167c3B;
    address public constant SD_IFO = 0x34d774B06d45bd3db9D51724Fc98Dc097A58eF27;

    function run() public {
        vm.createSelectFork("arbitrum");
        vm.startBroadcast(DAO.MAIN_DEPLOYER);
        IFOHelper ifoHelper = new IFOHelper(SD_IFO, CAKE.EXECUTOR);
        vm.stopBroadcast();
    }
}
