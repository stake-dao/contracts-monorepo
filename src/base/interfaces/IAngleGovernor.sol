// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IAngleGovernor {
    function getVotes(address account, uint256 timepoint) external view returns (uint256);

    function getVotesWithParams(address account, uint256 timepoint, bytes memory params) external view returns (uint256);

    function hasVoted(uint256 proposalId, address account) external view returns (bool);

    function proposalDeadline(uint256 proposalId) external view returns (uint256);

    function proposalSnapshot(uint256 proposalId) external view returns (uint256);

    function proposalVotes(uint256 proposalId) external view returns (uint256, uint256, uint256);

    function quorum(uint256 timepoint) external view returns (uint256);
}