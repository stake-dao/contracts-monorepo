// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import {CommonBase} from "test/common/CommonBase.sol";

// Base Spectra test overriding functions from CommonBase
abstract contract BaseSpectraTest is CommonBase, Test {
    constructor() {}

    function _deployLiquidityGauge(address _sdToken) internal returns (address _liquidityGauge) {
        _liquidityGauge = deployCode("vyper/LiquidityGaugeV4XChain.vy", abi.encode(_sdToken, address(this)));
    }
}
