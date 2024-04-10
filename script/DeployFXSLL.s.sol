// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {sdFXS} from "src/frax/fxs/token/sdFXS.sol";
import {FXSDepositor} from "src/frax/fxs/depositor/FXSDepositor.sol";
import {FxsLockerV2} from "src/frax/fxs/locker/FxsLockerV2.sol";

import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {Constants} from "src/base/utils/Constants.sol";

import {Frax} from "address-book/protocols/252.sol";

contract DeployFXSLL is Script {
    FXSDepositor internal depositor;
    FxsLockerV2 internal locker;
    sdFXS internal _sdFxs;
    ILiquidityGauge internal liquidityGauge;

    address internal constant LZ_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant GOVERNANCE = 0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765;
    address internal constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    error DEPLOYMENT_FAILED();

    function run() public {
        vm.startBroadcast(DEPLOYER);

        _sdFxs = new sdFXS("Stake DAO FXS", "sdFXS", LZ_ENDPOINT, GOVERNANCE);

        liquidityGauge =
            ILiquidityGauge(deployBytecode(Constants.LGV4_XCHAIN_BYTECODE, abi.encode(address(_sdFxs), GOVERNANCE)));

        locker = new FxsLockerV2(address(this), Frax.FXS, Frax.VEFXS);

        depositor = new FXSDepositor(Frax.FXS, address(locker), address(_sdFxs), address(liquidityGauge));

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
