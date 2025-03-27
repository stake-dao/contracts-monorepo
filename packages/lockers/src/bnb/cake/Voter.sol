// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IExecutor} from "src/common/interfaces/IExecutor.sol";

contract CakeVoter {
    /// @notice Address of the cake locker
    address public immutable locker;

    /// @notice Address of the pancake gauge controller
    address public immutable gaugeController;

    /// @notice Address of the governance
    address public governance;

    /// @notice Address of the future governance
    address public futureGovernance;

    /// @notice Executor contract
    IExecutor public executor;

    ////////////////////////////////////////////////////////////////
    // --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when an executor call failed
    error CALL_FAILED();

    /// @notice Error emitted when auth failed
    error GOVERNANCE();

    /// @notice Event emitted when governance is changed.
    /// @param newGovernance Address of the new governance.
    event GovernanceChanged(address indexed newGovernance);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    constructor(address _gaugeController, address _locker, address _executor, address _governance) {
        gaugeController = _gaugeController;
        locker = _locker;
        executor = IExecutor(_executor);
        governance = _governance;
    }

    ////////////////////////////////////////////////////////////////
    // --- VOTING
    ///////////////////////////////////////////////////////////////

    /// @notice Vote for a gauge
    /// @param _gauge Gauge to vote for
    /// @param _weight Weight to allocate for the gauge
    /// @param _chainId Chain id
    /// @param _skipNative Skip native or not
    /// @param _skipProxy Skip proxy or not
    function voteForGaugeWeights(address _gauge, uint256 _weight, uint256 _chainId, bool _skipNative, bool _skipProxy)
        external
        onlyGovernance
    {
        bytes memory voteData = abi.encodeWithSignature(
            "voteForGaugeWeights(address,uint256,uint256,bool,bool)", _gauge, _weight, _chainId, _skipNative, _skipProxy
        );
        (bool success,) = executor.callExecuteTo(locker, gaugeController, 0, voteData);
        if (!success) revert CALL_FAILED();
    }

    /// @notice Vote for gauges in bulk
    /// @param _gauges Gauges to vote for
    /// @param _weights Weights to allocate for gauges
    /// @param _chainIds Chain ids
    /// @param _skipNative Skip native or not
    /// @param _skipProxy Skip proxy or not
    function voteForGaugeWeightsBulk(
        address[] calldata _gauges,
        uint256[] calldata _weights,
        uint256[] calldata _chainIds,
        bool _skipNative,
        bool _skipProxy
    ) external onlyGovernance {
        bytes memory voteData = abi.encodeWithSignature(
            "voteForGaugeWeightsBulk(address[],uint256[],uint256[],bool,bool)",
            _gauges,
            _weights,
            _chainIds,
            _skipNative,
            _skipProxy
        );
        (bool success,) = executor.callExecuteTo(locker, gaugeController, 0, voteData);
        if (!success) revert CALL_FAILED();
    }

    ////////////////////////////////////////////////////////////////
    // --- GOVERNANCE
    ///////////////////////////////////////////////////////////////

    /// @notice Set the executor contract.
    /// @param _executor Address of the executor.
    function setExecutor(address _executor) external onlyGovernance {
        executor = IExecutor(_executor);
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
