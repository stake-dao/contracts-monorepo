// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import {CommonBase} from "test/common/CommonBase.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// end to end tests for the ZeroLend integration
abstract contract BaseZeroLendTest is CommonBase, Test {
    ERC20 WETH = ERC20(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f);

    constructor() {}

    function _deployLiquidityGauge(address _sdToken) internal returns (address _liquidityGauge) {
        // TODO confirm that can't deploy as proxy because LiquidityGaugeV4XChain doesn't have a initialize function
        _liquidityGauge = deployCode("vyper/LiquidityGaugeV4XChain.vy", abi.encode(_sdToken, address(this)));
    }
}
