// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IChildLiquidityGaugeFactory {
    function voting_escrow() external view returns (address);
    function is_valid_gauge(address _gauge) external view returns (bool);
}
