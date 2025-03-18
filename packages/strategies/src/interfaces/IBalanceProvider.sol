// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

interface IBalanceProvider {
    function balanceOf(address _address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}
