// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface ICakeDepositor {
    function deposit(uint256 _amount, bool _lock, bool _stake, address _user) external;

    function mintForCakeDelegator(address _user, uint256 _amount) external;
}
