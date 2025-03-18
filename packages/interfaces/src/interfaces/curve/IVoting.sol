// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IVoting {
    event CastVote(uint256 indexed voteId, address indexed voter, bool _supports, uint256 stake);
    event ChangeMinQuorum(uint64 minAcceptQuorumPct);
    event ChangeSupportRequired(uint64 supportRequiredPct);
    event ExecuteVote(uint256 indexed voteId);
    event MinimumBalanceSet(uint256 minBalance);
    event MinimumTimeSet(uint256 minTime);
    event RecoverToVault(address indexed vault, address indexed token, uint256 amount);
    event ScriptResult(address indexed executor, bytes script, bytes input, bytes returnData);
    event StartVote(
        uint256 indexed voteId,
        address indexed creator,
        string metadata,
        uint256 minBalance,
        uint256 minTime,
        uint256 totalSupply,
        uint256 creatorVotingPower
    );

    function changeMinAcceptQuorumPct(uint64 _minAcceptQuorumPct) external;
    function changeSupportRequiredPct(uint64 _supportRequiredPct) external;
    function disableVoteCreationOnce() external;
    function enableVoteCreationOnce() external;
    function executeVote(uint256 _voteId) external;
    function forward(bytes calldata _evmScript) external;
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
    function newVote(bytes calldata _executionScript, string calldata _metadata) external returns (uint256 voteId);
    function newVote(
        bytes calldata _executionScript,
        string calldata _metadata,
        bool _castVote,
        bool _executesIfDecided
    ) external returns (uint256 voteId);
    function setMinBalance(uint256 _minBalance) external;
    function setMinTime(uint256 _minTime) external;
    function transferToVault(address _token) external;
    function vote(uint256 _voteData, bool _supports, bool _executesIfDecided) external;
    function votePct(uint256 _voteId, uint256 _yeaPct, uint256 _nayPct, bool _executesIfDecided) external;
    function isForwarder() external pure returns (bool);
    function CREATE_VOTES_ROLE() external view returns (bytes32);
    function DISABLE_VOTE_CREATION() external view returns (bytes32);
    function ENABLE_VOTE_CREATION() external view returns (bytes32);
    function MODIFY_QUORUM_ROLE() external view returns (bytes32);
    function MODIFY_SUPPORT_ROLE() external view returns (bytes32);
    function PCT_BASE() external view returns (uint64);
    function SET_MIN_BALANCE_ROLE() external view returns (bytes32);
    function SET_MIN_TIME_ROLE() external view returns (bytes32);
    function allowRecoverability(address token) external view returns (bool);
    function appId() external view returns (bytes32);
    function canCreateNewVote(address _sender) external view returns (bool);
    function canExecute(uint256 _voteId) external view returns (bool);
    function canForward(address _sender, bytes calldata) external view returns (bool);
    function canPerform(address _sender, bytes32 _role, uint256[] calldata _params) external view returns (bool);
    function canVote(uint256 _voteId, address _voter) external view returns (bool);
    function enableVoteCreation() external view returns (bool);
    function getEVMScriptExecutor(bytes calldata _script) external view returns (address);
    function getEVMScriptRegistry() external view returns (address);
    function getInitializationBlock() external view returns (uint256);
    function getRecoveryVault() external view returns (address);
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
    function getVoterState(uint256 _voteId, address _voter) external view returns (uint8);
    function hasInitialized() external view returns (bool);
    function isPetrified() external view returns (bool);
    function kernel() external view returns (address);
    function lastCreateVoteTimes(address) external view returns (uint256);
    function minAcceptQuorumPct() external view returns (uint64);
    function minBalance() external view returns (uint256);
    function minBalanceLowerLimit() external view returns (uint256);
    function minBalanceUpperLimit() external view returns (uint256);
    function minTime() external view returns (uint256);
    function minTimeLowerLimit() external view returns (uint256);
    function minTimeUpperLimit() external view returns (uint256);
    function supportRequiredPct() external view returns (uint64);
    function token() external view returns (address);
    function voteTime() external view returns (uint64);
    function votesLength() external view returns (uint256);
}
