// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface ISdToken {
    function balanceOf(address account) external view returns (uint256);

    function burn(uint256 amount) external;

    function mint(address to, uint256 amount) external;

    function operator() external view returns (address);

    function setOperator(address _operator) external;
}
