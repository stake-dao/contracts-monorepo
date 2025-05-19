// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/src/Test.sol";
import {CommonBase} from "test/common/CommonBase.sol";
import {Common} from "address-book/src/CommonLinea.sol";

// end to end tests for the ZeroLend integration
abstract contract BaseZeroLendTest is CommonBase, Test {
    ERC20 internal WETH = ERC20(Common.WETH);

    constructor() {}

    function _deployLiquidityGauge(address _sdToken) internal returns (address _liquidityGauge) {
        _liquidityGauge = deployCode("vyper/LiquidityGaugeV4XChain.vy", abi.encode(_sdToken, address(this)));
    }
}
