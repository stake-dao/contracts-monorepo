// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {PendleAccumulatorV2} from "src/pendle/accumulator/PendleAccumulatorV2.sol";

contract DeployPendleAccumulatorV2 is Script, Test {

    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public daoRecipient = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public bountyRecipient = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public pendleVeSdtFeeProxy = 0x12992595328E52267c95e45B1a97014D6Ddf8683;

    PendleAccumulatorV2 public accumulator;

    function run() public {
        vm.startBroadcast(deployer);
        accumulator = new PendleAccumulatorV2(
            deployer, 
            daoRecipient, 
            bountyRecipient, 
            pendleVeSdtFeeProxy
        );
        vm.stopBroadcast();
    }
}