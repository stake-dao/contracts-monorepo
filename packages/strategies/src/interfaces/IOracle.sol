// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IOracle {
    function ORACLE_BASE_EXPONENT() external view returns (uint256);
    function price() external view returns (uint256);
}
