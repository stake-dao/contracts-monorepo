// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IVeBoost {
    function approve(address, uint256) external;
    function boost(address, uint256, uint256, address) external;
    function delegable_balance(address) external returns (uint256);
    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external;
    function received_balance(address) external returns (uint256);
}
