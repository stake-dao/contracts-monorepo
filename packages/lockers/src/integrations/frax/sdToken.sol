// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "src/integrations/frax/FXTLDelegation.sol";

/// @title sdFxsFraxtal
/// @author StakeDAO
/// @notice A token that represents the Token deposited by a user into the DepositorBase
/// @dev Minting & Burning was modified to be used by the operator
contract sdToken is ERC20, FXTLDelegation {
    /// @notice Address of the operator (can mint and burn)
    address public operator;

    /// @notice Throwed on Auth
    error OnlyOperator();

    modifier onlyOperator() {
        if (operator != msg.sender) revert OnlyOperator();
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _delegationRegistry Address of the fraxtal delegation registry
    /// @param _initialDelegate Address of the delegate that receives network reward
    constructor(string memory _name, string memory _symbol, address _delegationRegistry, address _initialDelegate)
        ERC20(_name, _symbol)
        FXTLDelegation(_delegationRegistry, _initialDelegate)
    {
        operator = msg.sender;
    }

    /// @notice Set a new operator that can mint and burn sdToken
    /// @param _operator new operator address
    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    /// @notice mint new sdToken, callable only by the operator
    /// @param _to recipient to mint for
    /// @param _amount amount to mint
    function mint(address _to, uint256 _amount) external onlyOperator {
        _mint(_to, _amount);
    }

    /// @notice burn sdToken, callable only by the operator
    /// @param _from sdToken holder
    /// @param _amount amount to burn
    function burn(address _from, uint256 _amount) external onlyOperator {
        _burn(_from, _amount);
    }
}
