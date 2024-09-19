// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/42161.sol";
import "address-book/src/lockers/42161.sol";

import "src/arbitrum/cake/IFOFactory.sol";

contract Deploy is Script {
    address public constant CAKE_IFO = 0xa6f907493269BEF3383fF0CBFd25e1Cc35167c3B;

    function run() public {
        vm.createSelectFork("arbitrum");
        vm.startBroadcast(DAO.MAIN_DEPLOYER);
        IFOFactory ifoFactory = new IFOFactory(CAKE.EXECUTOR, DAO.MAIN_DEPLOYER, DAO.GOVERNANCE);
        ifoFactory.createIFO(CAKE_IFO);
        ifoFactory.transferGovernance(DAO.GOVERNANCE);
        vm.stopBroadcast();
    }
}
