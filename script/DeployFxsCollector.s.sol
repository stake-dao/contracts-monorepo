// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {DAO} from "address-book/dao/1.sol";
import {FxsCollectorERC20} from "src/frax/fxs/collector/FxsCollectorERC20.sol";

contract DeployFxsCollector is Script {
    FxsCollectorERC20 internal collector;

    address internal constant DELEGATION_REGISTRY = 0x4392dC16867D53DBFE227076606455634d4c2795;
    address internal constant INITIAL_DELEGATE = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address internal constant GOVERNANCE = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        collector = new FxsCollectorERC20(GOVERNANCE, DELEGATION_REGISTRY, INITIAL_DELEGATE);

        vm.stopBroadcast();
    }
}
