// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IPendleStrategy {
    function sdGauges(address) external view returns (address);

    function governance() external view returns (address);

    function setSdGauge(address gauge, address sdGauge) external;
}
