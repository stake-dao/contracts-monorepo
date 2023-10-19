// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IGaugeController {
    // solhint-disable-next-line
    function get_gauge_weight(address _gauge) external returns (uint256);
}
