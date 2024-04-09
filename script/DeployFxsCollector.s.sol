// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {DAO} from "address-book/dao/1.sol";
import {FxsCollectorFraxtal} from "src/frax/fxs/collector/FxsCollectorFraxtal.sol";
import {Constants} from "src/base/utils/Constants.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import "test/utils/Utils.sol";

contract DeployFxsCollector is Script {
    FxsCollectorFraxtal internal collector;
    ILiquidityGauge internal liquidityGaugeCollector;

    address internal constant DELEGATION_REGISTRY = 0x4392dC16867D53DBFE227076606455634d4c2795;
    address internal constant INITIAL_DELEGATE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;
    address internal constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address internal constant GOVERNANCE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;
    address internal constant CLAIMER = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        collector = new FxsCollectorFraxtal(DEPLOYER, DELEGATION_REGISTRY, INITIAL_DELEGATE);

        liquidityGaugeCollector = ILiquidityGauge(
            Utils.deployBytecode(
                Constants.LGV4_STRAT_FRAXTAL_NATIVE_BYTECODE,
                abi.encode(
                    address(collector), GOVERNANCE, address(collector), CLAIMER, DELEGATION_REGISTRY, INITIAL_DELEGATE
                )
            )
        );

        collector.setCollectorGauge(address(liquidityGaugeCollector));

        collector.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
