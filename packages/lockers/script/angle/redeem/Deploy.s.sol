// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "forge-std/src/Script.sol";
import "src/common/locker/Redeem.sol";

contract Deploy is Script {
    function run() public {
        vm.createSelectFork("mainnet");
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        /// @notice The conversion rate is 0.922165662297322400 ANGLE per 1e18 SDANGLE.
        uint256 conversionRate = 922165662297322400;

        new Redeem(address(ANGLE.TOKEN), address(ANGLE.SDTOKEN), address(ANGLE.GAUGE), conversionRate);

        vm.stopBroadcast();
    }
}
