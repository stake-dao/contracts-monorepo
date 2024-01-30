// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IAngleGovernor {
    function castVote(uint256 proposalId, uint8 support) external returns (uint256 weight);

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason)
        external
        returns (uint256 weight);

    function castVoteWithReasonAndParams(uint256 proposalId, uint8 support, string calldata reason, bytes memory params)
        external
        returns (uint256 weight);
}
