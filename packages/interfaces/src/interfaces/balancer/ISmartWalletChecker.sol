// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface ISmartWalletChecker {
    event ContractAddressAdded(address contractAddress);
    event ContractAddressRemoved(address contractAddress);

    function allowlistAddress(address contractAddress) external;
    function denylistAddress(address contractAddress) external;
    function check(address contractAddress) external view returns (bool);
    function getActionId(bytes4 selector) external view returns (bytes32);
    function getAllowlistedAddress(uint256 index) external view returns (address);
    function getAllowlistedAddressesLength() external view returns (uint256);
    function getAuthorizer() external view returns (address);
    function getVault() external view returns (address);
}
