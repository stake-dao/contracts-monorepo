// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface ISdToken {
    function setOperator(address _operator) external;
    function balanceOf(address account) external view returns (uint256);
    function operator() external view returns (address);
}
