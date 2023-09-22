// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {OFT} from "solidity-examples/token/oft/OFT.sol";

/// @title sdMAVOft
/// @author StakeDAO
/// @notice A token that represents the Token deposited by a user into the Depositor
/// @dev Minting & Burning was modified to be used by the operator
contract sdMAV is OFT {

    error ONLY_OPERATOR();

    address public operator;

    constructor(string memory _name, string memory _symbol, address _lzEndpoint) OFT(_name, _symbol, _lzEndpoint) {
        operator = msg.sender;
    }

    /// @notice Set a new operator that can mint and burn sdToken
    /// @param _operator new operator address
    function setOperator(address _operator) external {
        if (msg.sender != operator) revert ONLY_OPERATOR();
        operator = _operator;
    }

    /// @notice mint new sdToken, callable only by the operator
    /// @param _to recipient to mint for
    /// @param _amount amount to mint
    function mint(address _to, uint256 _amount) external {
        if (msg.sender != operator) revert ONLY_OPERATOR();
        _mint(_to, _amount);
    }

    /// @notice burn sdToken, callable only by the operator
    /// @param _from sdToken holder
    /// @param _amount amount to burn
    function burn(address _from, uint256 _amount) external {
        if (msg.sender != operator) revert ONLY_OPERATOR();
        _burn(_from, _amount);
    }
}
