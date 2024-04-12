// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {OFT} from "LayerZero-v2/oft/OFT.sol";

/// @title sdFxsOftV2
/// @author StakeDAO
/// @notice A token that represents the Token deposited by a user into the Depositor
/// @dev Minting & Burning was modified to be used by the operator
contract sdFXSFraxtal is OFT {
    address public operator;

    error CallFailed();
    error OnlyOperator();

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _oftDelegate,
        address _delegationRegistry,
        address _initialDelegate
    ) OFT(_name, _symbol, _lzEndpoint, _oftDelegate) {
        operator = msg.sender;

        // Custom code for Fraxtal
        // set _initialDelegate as delegate
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert CallFailed();
        // disable self managing delegation
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert CallFailed();
    }

    /// @notice Set a new operator that can mint and burn sdToken
    /// @param _operator new operator address
    function setOperator(address _operator) external {
        if (msg.sender != operator) revert OnlyOperator();
        operator = _operator;
    }

    /// @notice mint new sdToken, callable only by the operator
    /// @param _to recipient to mint for
    /// @param _amount amount to mint
    function mint(address _to, uint256 _amount) external {
        if (msg.sender != operator) revert OnlyOperator();
        _mint(_to, _amount);
    }

    /// @notice burn sdToken, callable only by the operator
    /// @param _from sdToken holder
    /// @param _amount amount to burn
    function burn(address _from, uint256 _amount) external {
        if (msg.sender != operator) revert OnlyOperator();
        _burn(_from, _amount);
    }
}
