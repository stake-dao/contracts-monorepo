// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface ISmartWalletChecker {
    function check(address smartWallet) external view returns (bool);
    function approveWallet(address smartWallet) external;
    function revokeWallet(address smartWallet) external;
    function owner() external view returns (address);
}
