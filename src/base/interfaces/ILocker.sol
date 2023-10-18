// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ILocker {
    function setStrategy(address _strategy) external;
}