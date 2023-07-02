// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

/// @title  Counter
/// @notice Describe what the contract does
/// @author Stake DAO (Labs ?)
/// @custom:contact contact@stakedao.org
contract Counter {
    /// @notice Describe what this variable does
    uint256 public number;

    /// @notice Describe what this function does
    /// @param newNumber Describe this parameter
    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    /// @notice Describe what this function does
    function increment() public {
        number++;
    }
}
