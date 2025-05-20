// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IMiniMeToken.sol";

interface IVoting {
    enum VoterState { Absent, Yea, Nay, Even }

    struct Vote {
        bool executed;
        uint64 startDate;
        uint64 snapshotBlock;
        uint64 supportRequiredPct;
        uint64 minAcceptQuorumPct;
        uint256 yea;
        uint256 nay;
        uint256 votingPower;
        bytes executionScript;
        // mapping (address => VoterState) voters; // Not allowed in interface
    }

    event StartVote(uint256 indexed voteId, address indexed creator, string metadata, uint256 minBalance, uint256 minTime, uint256 totalSupply, uint256 creatorVotingPower);
    event CastVote(uint256 indexed voteId, address indexed voter, bool supports, uint256 stake);
    event ExecuteVote(uint256 indexed voteId);
    event ChangeSupportRequired(uint64 supportRequiredPct);
    event ChangeMinQuorum(uint64 minAcceptQuorumPct);
    event MinimumBalanceSet(uint256 minBalance);
    event MinimumTimeSet(uint256 minTime);

    function initialize(
        address _token,
        uint64 _supportRequiredPct,
        uint64 _minAcceptQuorumPct,
        uint64 _voteTime,
        uint256 _minBalance,
        uint256 _minTime,
        uint256 _minBalanceLowerLimit,
        uint256 _minBalanceUpperLimit,
        uint256 _minTimeLowerLimit,
        uint256 _minTimeUpperLimit
    ) external;

    function changeSupportRequiredPct(uint64 _supportRequiredPct) external;
    function changeMinAcceptQuorumPct(uint64 _minAcceptQuorumPct) external;
    function setMinBalance(uint256 _minBalance) external;
    function setMinTime(uint256 _minTime) external;
    function disableVoteCreationOnce() external;
    function enableVoteCreationOnce() external;
    function newVote(bytes calldata _executionScript, string calldata _metadata) external returns (uint256 voteId);
    function newVote(bytes calldata _executionScript, string calldata _metadata, bool _castVote, bool _executesIfDecided) external returns (uint256 voteId);
    function vote(uint256 _voteData, bool _supports, bool _executesIfDecided) external;
    function votePct(uint256 _voteId, uint256 _yeaPct, uint256 _nayPct, bool _executesIfDecided) external;
    function executeVote(uint256 _voteId) external;
    function isForwarder() external pure returns (bool);
    function forward(bytes calldata _evmScript) external;
    function canForward(address _sender, bytes calldata _evmScript) external view returns (bool);
    function canExecute(uint256 _voteId) external view returns (bool);
    function canVote(uint256 _voteId, address _voter) external view returns (bool);
    function canCreateNewVote(address _sender) external view returns (bool);
    function getVote(uint256 _voteId)
        external
        view
        returns (
            bool open,
            bool executed,
            uint64 startDate,
            uint64 snapshotBlock,
            uint64 supportRequired,
            uint64 minAcceptQuorum,
            uint256 yea,
            uint256 nay,
            uint256 votingPower,
            bytes memory script
        );
    function getVoterState(uint256 _voteId, address _voter) external view returns (VoterState);
}
