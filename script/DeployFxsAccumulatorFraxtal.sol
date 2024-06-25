// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {FxsAccumulatorFraxtal} from "src/frax/fxs/accumulator/FxsAccumulatorFraxtal.sol";

contract DeployFxsAccumulatoFraxtal is Script {
    FxsAccumulatorFraxtal public accumulator;

    address public constant GAUGE = 0x12992595328E52267c95e45B1a97014D6Ddf8683;
    address public constant LOCKER = 0x26aCff2adc9104FE1c26c958dC4C9a5180840c35;
    address public constant GOVERNANCE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;
    address internal constant DELEGATION_REGISTRY = 0x098c837FeF2e146e96ceAF58A10F68Fc6326DC4C;
    address internal constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        require(block.chainid == 252, "wrong network");
        accumulator = new FxsAccumulatorFraxtal(GAUGE, LOCKER, GOVERNANCE, DELEGATION_REGISTRY, GOVERNANCE);

        vm.stopBroadcast();
    }
}
