// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/src/Test.sol";
import {CommonBase} from "test/common/CommonBase.sol";

// end to end tests for the ZeroLend integration
abstract contract BaseZeroLendTest is CommonBase, Test {
    ERC20 internal WETH = ERC20(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f);

    constructor() {}

    function _deployLiquidityGauge(address _sdToken) internal returns (address _liquidityGauge) {
        _liquidityGauge = deployCode("vyper/LiquidityGaugeV4XChain.vy", abi.encode(_sdToken, address(this)));
    }
}
