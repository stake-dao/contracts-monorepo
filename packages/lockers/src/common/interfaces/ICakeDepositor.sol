// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface ICakeDepositor {
    function deposit(uint256 _amount, bool _lock, bool _stake, address _user) external;

    function mintForCakeDelegator(address _user, uint256 _amount) external;
}
