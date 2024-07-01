// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/base/interfaces/IVault.sol";
import "src/base/interfaces/IAdapter.sol";
import "src/base/interfaces/IStrategy.sol";
import "src/base/interfaces/ICakeV2Wrapper.sol";
import "src/base/interfaces/IAdapterRegistry.sol";

import {LibClone} from "solady/src/utils/LibClone.sol";

/// @notice Temporary contract to deploy new adapters.
contract AdapterFactory {
    using LibClone for address;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance contract.
    address public futureGovernance;

    /// @notice Address of the strategy.
    address public immutable strategy;

    /// @notice Mapping of adapter implementations per protocol.
    mapping(string => address) public adapterImplementations;

    address public immutable adapterRegistry;

    event GovernanceChanged(address indexed newGovernance);

    error GOVERNANCE();
    error INVALID_GAUGE();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    constructor(address _adapterRegistry, address _strategy) {
        strategy = _strategy;
        governance = msg.sender;
        adapterRegistry = _adapterRegistry;
    }

    function deploy(address _vault) external returns (address _adapterAddress) {
        /// Check for the gauge address.
        address lpToken = IVault(_vault).token();
        address gauge = IStrategy(strategy).gauges(lpToken);
        if (gauge == address(0)) revert INVALID_GAUGE();

        /// Check for the protocol adapter needed.
        /// This call will revert if the adapter is not found/needed.
        address adapter = ICakeV2Wrapper(gauge).adapterAddr();
        address adapterImplementation = adapterImplementations[IAdapter(adapter).PROTOCOL()];

        /// Build the parameters for the adapter.
        address _token0 = IAdapter(adapter).token0();
        address _token1 = IAdapter(adapter).token1();

        bytes32 _salt = keccak256(abi.encodePacked(_vault, gauge, adapterImplementation));
        bytes memory _data = abi.encodePacked(_vault, lpToken, _token0, _token1);

        // Clone the adapter.
        _adapterAddress = adapterImplementation.cloneDeterministic(_data, _salt);

        /// Set the adapter in the registry.
        IAdapterRegistry(adapterRegistry).setAdapter(_vault, _adapterAddress);
    }

    /// @notice Set the implementation for a protocol.
    /// @param _protocol Protocol name.
    /// @param _adapterImplementation Address of the adapter implementation.
    function setAdapterImplementation(string memory _protocol, address _adapterImplementation)
        external
        onlyGovernance
    {
        adapterImplementations[_protocol] = _adapterImplementation;
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert GOVERNANCE();

        governance = msg.sender;
        futureGovernance = address(0);
        emit GovernanceChanged(msg.sender);
    }
}
