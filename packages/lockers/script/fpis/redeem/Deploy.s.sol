// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";

import "src/mainnet/fpis/Redeem.sol";

contract Deploy is Script {
    function run() public {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        new Redeem(address(FPIS.TOKEN), address(FPIS.SDTOKEN), address(FPIS.GAUGE));

        vm.stopBroadcast();
    }
}
