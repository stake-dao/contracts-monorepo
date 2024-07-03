// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "test/common/BaseAccumulatorTest.sol";
import "src/mainnet/fx/accumulator/FXNAccumulator.sol";

contract AccumulatorTest is BaseAccumulatorTest {
    address internal constant WSETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    constructor() BaseAccumulatorTest(20_187_797, FXN.LOCKER, FXN.SDTOKEN, Fx.VEFXN, FXN.GAUGE, WSETH, FXN.TOKEN) {}

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new FXNAccumulator(address(liquidityGauge), locker, address(this)));
    }
}
