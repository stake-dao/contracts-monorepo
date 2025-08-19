// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {SYASDCRVAdapter} from "src/integrations/curve/SYASDCRVAdapter.sol";

contract DeploySYasdCRVAdapter is Script {
    function run() public returns (SYASDCRVAdapter adapter) {
        vm.createSelectFork("mainnet");

        vm.startBroadcast();
        adapter = new SYASDCRVAdapter();
        vm.stopBroadcast();
    }
}
