// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ILocker} from "src/base/interfaces/ILocker.sol";
import {IExecutor} from "src/base/interfaces/IExecutor.sol";

contract FXNVoter {
    /// @notice Address of the cake locker
    address public immutable locker;

    /// @notice Address of the pancake gauge controller
    address public immutable gaugeController;

    /// @notice Address of the governance
    address public governance;

    /// @notice Address of the future governance
    address public futureGovernance;

    /// @notice Error emitted when an executor call failed
    error CallFailed();

    /// @notice Error emitted on auth
    error NotAllowed();

    /// @notice Event emitted when the future governance accept the gov
    event GovernanceChanged(address governance);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotAllowed();
        _;
    }

    constructor(address _gaugeController, address _locker, address _governance) {
        locker = _locker;
        gaugeController = _gaugeController;
        governance = _governance;
    }

    /// @notice Vote for the gauge weights
    /// @param _gauges Array of gauge addresses
    /// @param _weights Array of weights
    function voteGauges(address[] calldata _gauges, uint256[] calldata _weights) external onlyGovernance {
        if(_gauges.length != _weights.length) revert NotAllowed();

        uint256 length = _gauges.length;
        for (uint256 i; i < length; i++) {
            bytes memory voteData =
                abi.encodeWithSignature("vote_for_gauge_weights(address,uint256)", _gauges[i], _weights[i]);
            (bool success,) = IExecutor(locker).execute(gaugeController, 0, voteData);
            require(success, "Voting failed!");
        }
    }

    /// @notice Call the execute function in another compatible contract
    /// @param _to Address of the contract to interact with the execute()
    /// @param _value Value to send to the _to contract.
    /// @param _data Data to send to the _to contract.
    /// @return success_ Boolean indicating if the execution was successful.
    function execute(address _to, uint256 _value, bytes calldata _data)
        external
        onlyGovernance
        returns (bool success_, bytes memory result_)
    {
        (success_, result_) = ILocker(locker).execute(_to, _value, _data);
    }

    /// @notice Execute a function.
    /// @param _to Address of the contract to execute.
    /// @param _value Value to send to the contract.
    /// @param _data Data to send to the contract.
    /// @return success_ Boolean indicating if the execution was successful.
    /// @return result_ Bytes containing the result of the execution.
    function executeTo(address _to, uint256 _value, bytes calldata _data)
        external
        onlyGovernance
        returns (bool success_, bytes memory result_)
    {
        (success_, result_) = _to.call{value: _value}(_data);
    }

    function acceptLockerGovernance() external onlyGovernance {
        ILocker(locker).acceptGovernance();
    }

    function transferLockerGovernance(address _governance) external onlyGovernance {
        ILocker(locker).transferGovernance(_governance);
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert NotAllowed();

        governance = msg.sender;
        futureGovernance = address(0);

        emit GovernanceChanged(msg.sender);
    }
}
