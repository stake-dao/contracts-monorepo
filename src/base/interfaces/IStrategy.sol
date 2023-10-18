// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IStrategy {
    function feeReceiver() external view returns (address);

    function protocolFeesPercent() external view returns (uint256);

    function withdraw(address _token, uint256 _amount, address _to) external;
}