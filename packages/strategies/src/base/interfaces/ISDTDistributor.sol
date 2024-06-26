// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ISDTDistributor {
    function distribute(address gaugeAddr) external;
}
