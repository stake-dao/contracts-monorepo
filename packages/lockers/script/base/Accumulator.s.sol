// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";

import "src/base/accumulator/AccumulatorV2.sol";

abstract contract Accumulator is Script {
    address payable internal accumulator;

    address[] feeSplitReceivers = new address[](2);
    uint256[] feeSplitFees = new uint256[](2);

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        accumulator = _deployAccumulator();

        feeSplitReceivers[0] = address(DAO.TREASURY);
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = address(DAO.LIQUIDITY_FEES_RECIPIENT);
        feeSplitFees[1] = 1000; // 5% to liquidity

        AccumulatorV2(accumulator).setFeeSplit(feeSplitReceivers, feeSplitFees);

        _afterDeploy();

        AccumulatorV2(accumulator).transferGovernance(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }

    function _deployAccumulator() internal virtual returns (address payable);

    function _afterDeploy() internal virtual;
}
