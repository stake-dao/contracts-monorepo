// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {SYASDPENDLEAdapter} from "src/integrations/pendle/SYASDPENDLEAdapter.sol";

contract DeploySYasdPENDLEAdapter is Script {
    function run() public returns (SYASDPENDLEAdapter adapter) {
        vm.createSelectFork("mainnet");

        vm.startBroadcast();
        adapter = new SYASDPENDLEAdapter();
        vm.stopBroadcast();
    }
}
