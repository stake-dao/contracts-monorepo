// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

/// @notice Registry of vault adapters.
contract AdapterRegistry {
    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance contract.
    address public futureGovernance;

    /// @notice Mapping of adapters per vault.
    mapping(address => address) public adapters;

    /// @notice Mapping of allowed contracts to update the adapters.
    mapping(address => bool) public allowed;

    error NOT_ALLOWED();

    error GOVERNANCE();

    modifier onlyAllowed() {
        if (!allowed[msg.sender]) revert NOT_ALLOWED();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    constructor() {
        governance = msg.sender;
    }

    /// @notice Get the adapter for a vault.
    function getAdapter(address _vault) external view returns (address) {
        return adapters[_vault];
    }

    /// @notice Set the adapter for a vault.
    /// @param _vault Address of the vault.
    /// @param _adapter Address of the adapter.
    function setAdapter(address _vault, address _adapter) external onlyAllowed {
        adapters[_vault] = _adapter;
    }

    /// @notice Set the allowed status of a contract.
    /// @param _contract Address of the contract.
    function setAllowed(address _contract, bool _allowed) external onlyGovernance {
        allowed[_contract] = _allowed;
    }

    /// @notice Set the future governance address.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance role.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert GOVERNANCE();

        governance = futureGovernance;
        futureGovernance = address(0);
    }
}
