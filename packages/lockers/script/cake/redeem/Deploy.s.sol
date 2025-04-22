// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "address-book/src/dao/56.sol";
import "address-book/src/lockers/56.sol";

import "forge-std/src/Script.sol";
import "src/common/locker/Redeem.sol";

contract Deploy is Script {
    function run() public {
        vm.createSelectFork("bnb");
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        new Redeem({
            _token: address(CAKE.TOKEN),
            _sdToken: address(CAKE.SDTOKEN),
            _sdTokenGauge: address(CAKE.GAUGE),
            _conversionRate: 1e18,
            _redeemCooldownDuration: 27 weeks,
            _owner: DAO.GOVERNANCE
        });

        vm.stopBroadcast();
    }
}
