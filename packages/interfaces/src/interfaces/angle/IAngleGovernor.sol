// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IAngleGovernor {
    event EIP712DomainChanged();
    event LateQuorumVoteExtensionSet(uint64 oldVoteExtension, uint64 newVoteExtension);
    event ProposalCanceled(uint256 proposalId);
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 voteStart,
        uint256 voteEnd,
        string description
    );
    event ProposalExecuted(uint256 proposalId);
    event ProposalExtended(uint256 indexed proposalId, uint64 extendedDeadline);
    event ProposalQueued(uint256 proposalId, uint256 etaSeconds);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);
    event QuorumNumeratorUpdated(uint256 oldQuorumNumerator, uint256 newQuorumNumerator);
    event ShortCircuitNumeratorUpdated(uint256 oldShortCircuitNumerator, uint256 newShortCircuitNumerator);
    event TimelockChange(address indexed oldTimelock, address indexed newTimelock);
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);
    event VoteCastWithParams(
        address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason, bytes params
    );
    event VotingDelayBlocksSet(uint256 oldVotingDelayBlocks, uint256 newVotingDelayBlocks);
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    function cancel(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        bytes32 descriptionHash
    ) external returns (uint256);
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);
    function castVoteBySig(uint256 proposalId, uint8 support, address voter, bytes calldata signature)
        external
        returns (uint256);
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external returns (uint256);
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes calldata params
    ) external returns (uint256);
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        string calldata reason,
        bytes calldata params,
        bytes calldata signature
    ) external returns (uint256);
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        returns (bytes4);
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4);
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string calldata description
    ) external returns (uint256);
    function queue(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        bytes32 descriptionHash
    ) external returns (uint256);
    function setLateQuorumVoteExtension(uint48 newVoteExtension) external;
    function setProposalThreshold(uint256 newProposalThreshold) external;
    function setVotingDelay(uint48 newVotingDelay) external;
    function setVotingDelayBlocks(uint256 newVotingDelayBlocks) external;
    function setVotingPeriod(uint32 newVotingPeriod) external;
    function updateQuorumNumerator(uint256 newQuorumNumerator) external;
    function updateShortCircuitNumerator(uint256 newShortCircuitNumerator) external;
    function updateTimelock(address newTimelock) external;
    function execute(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256);
    function relay(address target, uint256 value, bytes calldata data) external payable;
    function CLOCK_MODE() external pure returns (string memory);
    function COUNTING_MODE() external pure returns (string memory);
    function hashProposal(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        bytes32 descriptionHash
    ) external pure returns (uint256);
    function $snapshotTimestampToSnapshotBlockNumber(uint256 snapshot) external view returns (uint256 blockNumber);
    function $votingDelayBlocks() external view returns (uint256);
    function BALLOT_TYPEHASH() external view returns (bytes32);
    function EXTENDED_BALLOT_TYPEHASH() external view returns (bytes32);
    function clock() external view returns (uint48);
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
    function getVotes(address account, uint256 timepoint) external view returns (uint256);
    function getVotesWithParams(address account, uint256 timepoint, bytes calldata params)
        external
        view
        returns (uint256);
    function hasVoted(uint256 proposalId, address account) external view returns (bool);
    function lateQuorumVoteExtension() external view returns (uint48);
    function name() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
    function proposalDeadline(uint256 proposalId) external view returns (uint256);
    function proposalEta(uint256 proposalId) external view returns (uint256);
    function proposalNeedsQueuing(uint256) external view returns (bool);
    function proposalProposer(uint256 proposalId) external view returns (address);
    function proposalSnapshot(uint256 proposalId) external view returns (uint256);
    function proposalThreshold() external view returns (uint256);
    function proposalVotes(uint256 proposalId)
        external
        view
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes);
    function quorum(uint256 timepoint) external view returns (uint256 quorumAtTimepoint);
    function quorumDenominator() external view returns (uint256);
    function quorumNumerator(uint256 timepoint) external view returns (uint256);
    function quorumNumerator() external view returns (uint256);
    function shortCircuitNumerator() external view returns (uint256 latestShortCircuitNumerator);
    function shortCircuitNumerator(uint256 timepoint)
        external
        view
        returns (uint256 shortCircuitNumeratorAtTimepoint);
    function shortCircuitThreshold(uint256 timepoint)
        external
        view
        returns (uint256 shortCircuitThresholdAtTimepoint);
    function state(uint256 proposalId) external view returns (uint8);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function timelock() external view returns (address);
    function token() external view returns (address);
    function veANGLEVotingDelegation() external view returns (address);
    function version() external view returns (string memory);
    function voteWeightCast(uint256 proposalId, address account) external view returns (uint128);
    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
}
