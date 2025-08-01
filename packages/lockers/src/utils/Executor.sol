// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

interface IExecuteCompatible {
    function execute(address _to, uint256 _value, bytes memory _data) external returns (bool, bytes memory);
}

/// @notice Main access point of Locker.
contract Executor {
    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance.
    address public futureGovernance;

    /// @notice Mapping of allowed addresses
    mapping(address => bool) public allowed; // contract -> allowed or not

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when input address is null
    error AddressNull();

    /// @notice Error emitted when auth failed
    error Governance();

    /// @notice Error emitted when try to allow an eoa
    error NotContract();

    /// @notice Error emitted when auth failed (gor or allowed)
    error Unauthorized();

    /// @notice Event emitted when a new contract is allowed
    event Allowed(address user);

    /// @notice Event emitted when a new contract id disallowed
    event Disallowed(address user);

    /// @notice Event emitted when governance change
    event GovernanceChanged(address gov);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert Governance();
        _;
    }

    modifier onlyGovernanceOrAllowed() {
        if (msg.sender != governance && !allowed[msg.sender]) revert Unauthorized();
        _;
    }

    constructor(address _governance) {
        governance = _governance;
    }

    /// @notice Call the execute function in another compatible contract
    /// @param _executor Address of the contract to call the execute().
    /// @param _to Address of the contract to interact with the execute()
    /// @param _value Value to send to the _to contract.
    /// @param _data Data to send to the _to contract.
    /// @return success_ Boolean indicating if the execution was successful.
    function callExecuteTo(address _executor, address _to, uint256 _value, bytes calldata _data)
        external
        onlyGovernanceOrAllowed
        returns (bool success_, bytes memory result_)
    {
        (success_, result_) = IExecuteCompatible(_executor).execute(_to, _value, _data);
    }

    /// @notice Execute a function.
    /// @param _to Address of the contract to execute.
    /// @param _value Value to send to the contract.
    /// @param _data Data to send to the contract.
    /// @return success_ Boolean indicating if the execution was successful.
    /// @return result_ Bytes containing the result of the execution.
    function execute(address _to, uint256 _value, bytes calldata _data)
        external
        onlyGovernanceOrAllowed
        returns (bool success_, bytes memory result_)
    {
        (success_, result_) = _to.call{value: _value}(_data);
    }

    /// @notice Allow a module to interact with the `execute` function.
    /// @dev excodesize can be bypassed but whitelist should go through governance.
    function allowAddress(address _address) external onlyGovernance {
        if (_address == address(0)) revert AddressNull();

        /// Check if the address is a contract.
        int256 size;
        assembly {
            size := extcodesize(_address)
        }
        if (size == 0) revert NotContract();

        allowed[_address] = true;

        emit Allowed(_address);
    }

    /// @notice Disallow a module to interact with the `execute` function.
    function disallowAddress(address _address) external onlyGovernance {
        allowed[_address] = false;
        emit Disallowed(_address);
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert Governance();

        governance = msg.sender;
        futureGovernance = address(0);

        emit GovernanceChanged(msg.sender);
    }
}
