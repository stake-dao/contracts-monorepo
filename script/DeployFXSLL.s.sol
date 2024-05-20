// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {sdFXSFraxtal} from "src/frax/fxs/token/sdFXSFraxtal.sol";
import {FXSDepositorFraxtal} from "src/frax/fxs/depositor/FXSDepositorFraxtal.sol";
import {FxsLockerFraxtal} from "src/frax/fxs/locker/FxsLockerFraxtal.sol";

import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {Constants} from "src/base/utils/Constants.sol";

import {Frax} from "address-book/protocols/252.sol";
import {FXS} from "address-book/lockers/1.sol";

contract DeployFXSLL is Script {
    FXSDepositorFraxtal internal depositor;
    FxsLockerFraxtal internal locker;
    sdFXSFraxtal internal _sdFxs;
    ILiquidityGauge internal liquidityGauge;

    address internal constant GOVERNANCE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;
    address internal constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address internal constant DELEGATION_REGISTRY = 0xF5cA906f05cafa944c27c6881bed3DFd3a785b6A;
    address internal constant FRAXTAL_BRIDGE = 0x4200000000000000000000000000000000000010;

    error DEPLOYMENT_FAILED();

    function run() public {
        vm.startBroadcast(DEPLOYER);

        _sdFxs =
            new sdFXSFraxtal("Stake DAO FXS", "sdFXS", FRAXTAL_BRIDGE, FXS.SDTOKEN, DELEGATION_REGISTRY, GOVERNANCE);

        liquidityGauge = ILiquidityGauge(
            deployBytecode(
                Constants.LGV4_NATIVE_FRAXTAL_BYTECODE,
                abi.encode(address(_sdFxs), GOVERNANCE, DELEGATION_REGISTRY, GOVERNANCE)
            )
        );

        locker = new FxsLockerFraxtal(address(this), Frax.FXS, Frax.VEFXS, DELEGATION_REGISTRY, GOVERNANCE);

        depositor = new FXSDepositorFraxtal(
            Frax.FXS, address(locker), address(_sdFxs), address(liquidityGauge), DELEGATION_REGISTRY, GOVERNANCE
        );

        locker.setDepositor(address(depositor));
        _sdFxs.setOperator(address(depositor));

        depositor.transferGovernance(GOVERNANCE);
        locker.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) public returns (address deployed) {
        if (args.length > 0) {
            bytecode = abi.encodePacked(bytecode, args);
        }

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        if (deployed == address(0)) revert DEPLOYMENT_FAILED();
    }
}
