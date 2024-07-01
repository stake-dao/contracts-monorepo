// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";

import "src/curve/accumulator/CRVAccumulatorV3.sol";

contract DeployCRVAccumulatorV3 is Script {
    CRVAccumulatorV3 internal accumulator;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        accumulator = new CRVAccumulatorV3(CRV.GAUGE, CRV.LOCKER, DAO.MAIN_DEPLOYER);

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = address(DAO.TREASURY);
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = address(DAO.LIQUIDITY_FEES_RECIPIENT);
        feeSplitFees[1] = 1000; // 5% to liquidity

        accumulator.setFeeSplit(feeSplitReceivers, feeSplitFees);
        accumulator.transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
