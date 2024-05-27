// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";

import "src/base/fee/VBMRecipient.sol";
import "src/curve/accumulator/CRVAccumulatorV2.sol";

/// @title DeployCRVAccumulator - A script to deploy the CRV accumulator contract
contract DeployCRVAccumulator is Script {
    address public vbmRecipient;
    CRVAccumulatorV2 public accumulator;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        /// Deploy VBMRecipient.
        vbmRecipient = address(new VESDTRecipient());

        /// Deploy Accumulator.
        /// accumulator = new CRVAccumulatorV2(CRV.GAUGE, CRV.LOCKER, DAO.GOVERNANCE, vbmRecipient, DAO.GOVERNANCE);

        /// Steps to do after deployment.
        /// 1. Update the accumulator in the Gauge.
        /// 2. Update the accumulator in the strategy.
        /// 3. Update the accumulator in the workflows.
        /// 4. Set Repartition in the Fee Receiver.

        vm.stopBroadcast();
    }
}
