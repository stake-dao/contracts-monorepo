// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IExecutor} from "src/base/interfaces/IExecutor.sol";

contract AngleVoterV5 {
    /// @notice Address of the angle locker
    address public constant ANGLE_LOCKER = 0xD13F8C25CceD32cdfA79EB5eD654Ce3e484dCAF5;

    /// @notice Address of the angle gauge controller
    address public constant ANGLE_GC = 0x9aD7e7b0877582E14c17702EecF49018DD6f2367;

    /// @notice Address of the angle governor
    address public constant ANGLE_GOVERNOR = 0x748bA9Cd5a5DDba5ABA70a4aC861b2413dCa4436;

    /// @notice Address of the angle strategy
    address public angleStrategy = 0x22635427C72e8b0028FeAE1B5e1957508d9D7CAF;

    /// @notice Address of the governance
    address public governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    /// @notice Error emitted when a call fails
    error CallFailed();

    /// @notice Error emitted when the arrays have different length
    error DifferentLength();

    /// @notice Error emitted on auth
    error NotAllowed();

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotAllowed();
        _;
    }

    function castVote(uint256 _proposalId, uint8 _support) external onlyGovernance returns (uint256 _weight) {
        bytes memory voteData =
            abi.encodeWithSignature("castVote(uint256,uint8)", _proposalId, _support);
        (bool success, bytes memory result) = IExecutor(angleStrategy).execute(
                ANGLE_LOCKER, 0, abi.encodeWithSignature("execute(address,uint256,bytes)", ANGLE_GOVERNOR, 0, voteData)
            );
        if (!success) revert CallFailed();
        _weight = abi.decode(result, (uint256));
    }

    function castVoteWithReason(uint256 _proposalId, uint8 _support, string calldata _reason)
        external
        onlyGovernance
        returns (uint256 _weight)
    {
        bytes memory voteData =
            abi.encodeWithSignature("castVoteWithReason(uint256,uint8,string)", _proposalId, _support, _reason);
        (bool success, bytes memory result) = IExecutor(angleStrategy).execute(
                ANGLE_LOCKER, 0, abi.encodeWithSignature("execute(address,uint256,bytes)", ANGLE_GOVERNOR, 0, voteData)
            );
        if (!success) revert CallFailed();
        _weight = abi.decode(result, (uint256));
    }

    function castVoteWithReasonAndParams(
        uint256 _proposalId,
        uint8 _support,
        string calldata _reason,
        bytes memory _params
    ) external onlyGovernance returns (uint256 _weight) {
        bytes memory voteData =
            abi.encodeWithSignature("castVoteWithReasonAndParams(uint256,uint8,string,bytes)", _proposalId, _support, _reason, _params);
        (bool success, bytes memory result) = IExecutor(angleStrategy).execute(
                ANGLE_LOCKER, 0, abi.encodeWithSignature("execute(address,uint256,bytes)", ANGLE_GOVERNOR, 0, voteData)
            );
        if (!success) revert CallFailed();
        _weight = abi.decode(result, (uint256));
    }

    /// @notice vote for angle gauges
    /// @param _gauges gauges to vote for
    /// @param _weights vote weight for each gauge
    function voteGauges(address[] calldata _gauges, uint256[] calldata _weights) external onlyGovernance {
        if (_gauges.length != _weights.length) revert DifferentLength();
        uint256 length = _gauges.length;
        for (uint256 i; i < length;) {
            bytes memory voteData =
                abi.encodeWithSignature("vote_for_gauge_weights(address,uint256)", _gauges[i], _weights[i]);
            (bool success,) = IExecutor(angleStrategy).execute(
                ANGLE_LOCKER, 0, abi.encodeWithSignature("execute(address,uint256,bytes)", ANGLE_GC, 0, voteData)
            );
            if (!success) revert CallFailed();
            unchecked {
                ++i;
            }
        }
    }

    /// @notice execute a function
    /// @param _to Address to sent the value to
    /// @param _value Value to be sent
    /// @param _data Call function data
    function execute(address _to, uint256 _value, bytes calldata _data)
        external
        onlyGovernance
        returns (bool success, bytes memory result)
    {
        (success, result) = _to.call{value: _value}(_data);
        if (!success) revert CallFailed();
    }

    /// @notice execute a function and transfer funds to the given address
    /// @param _to Address to sent the value to
    /// @param _value Value to be sent
    /// @param _data Call function data
    /// @param _token address of the token that we will transfer
    /// @param _recipient address of the recipient that will get the tokens
    function executeAndTransfer(address _to, uint256 _value, bytes calldata _data, address _token, address _recipient)
        external
        onlyGovernance
        returns (bool success)
    {
        (success,) = _to.call{value: _value}(_data);
        if (!success) revert CallFailed();

        uint256 tokenBalance = ERC20(_token).balanceOf(ANGLE_LOCKER);
        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", _recipient, tokenBalance);
        bytes memory executeData = abi.encodeWithSignature("execute(address,uint256,bytes)", _token, 0, transferData);
        (success,) = IExecutor(angleStrategy).execute(ANGLE_LOCKER, 0, executeData);
        if (!success) revert CallFailed();
    }

    /* ========== SETTERS ========== */
    /// @notice set new governance
    /// @param _newGovernance governance address
    function setGovernance(address _newGovernance) external onlyGovernance {
        governance = _newGovernance;
    }

    /// @notice change strategy
    /// @param _newStrategy strategy address
    function changeStrategy(address _newStrategy) external onlyGovernance {
        angleStrategy = _newStrategy;
    }
}
