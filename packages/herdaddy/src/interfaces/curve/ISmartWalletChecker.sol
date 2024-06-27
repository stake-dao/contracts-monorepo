// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface ISmartWalletWhitelist {
    event ApproveWallet(address);
    event RevokeWallet(address);

    function applySetChecker() external;
    function approveWallet(address _wallet) external;
    function commitSetChecker(address _checker) external;
    function revokeWallet(address _wallet) external;
    function check(address _wallet) external view returns (bool);
    function checker() external view returns (address);
    function dao() external view returns (address);
    function future_checker() external view returns (address);
    function wallets(address) external view returns (bool);
}
