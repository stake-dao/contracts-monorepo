// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IExecutor} from "src/base/interfaces/IExecutor.sol";

contract CakeVoter {
    address public immutable cakeGC;

    address public immutable cakeLocker;

    address public governance;

    address public futureGovernance;

    IExecutor public executor;

    error CallFailed();

    error NotAllowed();

    event GovernanceChanged(address governance);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotAllowed();
        _;
    }

    constructor(address _cakeGC, address _cakeLocker, address _executor, address _governance) {
        cakeGC = _cakeGC;
        cakeLocker = _cakeLocker;
        executor = IExecutor(_executor);
        governance = _governance;
    }

    function voteForGaugeWeights(address _gauge, uint256 _weight, uint256 _chainId, bool _skipNative, bool _skipProxy)
        external
        onlyGovernance
    {
        bytes memory voteData = abi.encodeWithSignature(
            "voteForGaugeWeights(address,uint256,uint256,bool,bool)", _gauge, _weight, _chainId, _skipNative, _skipProxy
        );
        (bool success,) = executor.callExecuteTo(cakeLocker, cakeGC, 0, voteData);
        if (!success) revert CallFailed();
    }

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
        (bool success,) = executor.callExecuteTo(cakeLocker, cakeGC, 0, voteData);
        if (!success) revert CallFailed();
    }

    /* ========== SETTERS ========== */
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
        if (msg.sender != futureGovernance) revert NotAllowed();

        governance = msg.sender;
        futureGovernance = address(0);

        emit GovernanceChanged(msg.sender);
    }
}
