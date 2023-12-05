// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface ISmartWalletChecker {
    function check(address smartWallet) external view returns (bool);
    function approveWallet(address smartWallet) external;
    function revokeWallet(address smartWallet) external;
    function owner() external view returns (address);
}
