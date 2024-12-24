// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

abstract contract Governance {
    address public governance;
    address public futureGovernance;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when governance is changed.
    /// @param newGovernance Address of the new governance.
    event GovernanceChanged(address indexed newGovernance);

    /// @notice Error emitted when auth failed
    error OnlyGovernance();

    ////////////////////////////////////////////////////////////////
    /// --- MODIFIERS
    ///////////////////////////////////////////////////////////////

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    constructor(address _governance) {
        governance = _governance;
    }

    ////////////////////////////////////////////////////////////
    /// --- FUNCTIONS
    ////////////////////////////////////////////////////////////

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) public onlyGovernance {
        require(_governance != address(0), "Governance address cannot be 0x0");
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() public {
        if (msg.sender != futureGovernance) revert OnlyGovernance();

        governance = msg.sender;
        emit GovernanceChanged(msg.sender);
    }
}
