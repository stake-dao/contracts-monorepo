// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ISdToken} from "src/base/interfaces/ISdToken.sol";

/// @title sdTokenOperator
/// @author StakeDAO
/// @notice A middleware contract used to allow multi address to mint/burn sd token, it needs to be the sdToken's operator
contract sdTokenOperator {
    address public governance;

    address public futureGovernance;

    ISdToken public immutable sdToken;

    mapping(address => bool) public operators;

    error AlreadyAllowed();

    error NotAllowed();

    error Auth();

    event GovernanceChanged(address governance);

    event OperatorAllowed(address operator);

    event OperatorDisallowed(address operator);

    modifier onlyFutureGovernance() {
        if (msg.sender != futureGovernance) revert Auth();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert Auth();
        _;
    }

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert Auth();
        _;
    }

    constructor(address _sdToken, address _governance) {
        sdToken = ISdToken(_sdToken);
        governance = _governance;
    }

    /// @notice mint new sdToken, callable only by the operator
    /// @param _to recipient to mint for
    /// @param _amount amount to mint
    function mint(address _to, uint256 _amount) external onlyOperator {
        sdToken.mint(_to, _amount);
    }

    /// @notice burn sdToken, callable only by the operator
    /// @param _from sdToken holder
    /// @param _amount amount to burn
    function burn(address _from, uint256 _amount) external onlyOperator {
        sdToken.burn(_from, _amount);
    }

    /// @notice Allow a new operator that can mint and burn sdToken
    /// @param _operator new operator address
    function allowOperator(address _operator) external onlyGovernance {
        if (operators[_operator]) revert AlreadyAllowed();
        operators[_operator] = true;

        emit OperatorAllowed(_operator);
    }

    /// @notice Allow a new operator that can mint and burn sdToken
    /// @param _operator new operator address
    function disallowOperator(address _operator) external onlyGovernance {
        if (!operators[_operator]) revert NotAllowed();
        operators[_operator] = false;

        emit OperatorDisallowed(_operator);
    }

    /// @notice Set a new sdToken's operator, after this action the contract can't mint/burn
    /// @param _operator new operator address
    function setSdTokenOperator(address _operator) external onlyGovernance {
        sdToken.setOperator(_operator);
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external onlyFutureGovernance {
        governance = msg.sender;
        futureGovernance = address(0);
        emit GovernanceChanged(msg.sender);
    }
}
