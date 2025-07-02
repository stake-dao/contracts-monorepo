// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IVoting} from "@interfaces/curve/IVoting.sol";
import {CurveLocker, CurveProtocol} from "@address-book/src/CurveEthereum.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {VoterBase} from "src/VoterBase.sol";

enum VoteType {
    Ownership,
    Parameter
}

struct Vote {
    uint256 _voteId;
    uint256 _yeaPct;
    uint256 _nayPct;
    VoteType _voteType;
}

/// @title CurveVoter
/// @notice This contract manages all the voting related to Curve protocols
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract CurveVoter is VoterBase {
    using FixedPointMathLib for uint256;

    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Curve voter for ownership proposals
    address public immutable VOTER_OWNERSHIP = CurveProtocol.VOTING_APP_OWNERSHIP;

    /// @notice Curve voter for parameter proposals
    address public immutable VOTER_PARAMETER = CurveProtocol.VOTING_APP_PARAMETER;

    /// @notice Curve gauge controller
    address public immutable CONTROLLER = CurveProtocol.GAUGE_CONTROLLER;

    /// @notice Curve locker
    address public immutable LOCKER = CurveLocker.LOCKER;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when the pct is different than the voter pct
    error WRONG_PCT();

    /// @notice Error emitted when the vote type is not valid (neither Ownership nor Parameter)
    error WRONG_VOTE_TYPE();

    constructor(address _gateway) VoterBase(_gateway) {}

    ////////////////////////////////////////////////////////////////
    /// --- PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Bundle ownership and parameter votes
    /// @param _votes Array of votes to bundle
    /// @dev The given vote type must be either Ownership (0) or Parameter (1)
    /// @custom:throws WRONG_VOTE_TYPE when the vote type is not valid
    /// @custom:throws NotAuthorized when the caller is not allowed
    function votes(Vote[] calldata _votes) external hasProposalsOrAllPermission {
        uint256 length = _votes.length;

        // Vote for each proposal atomically
        for (uint256 i; i < length; i++) {
            Vote memory vote = _votes[i];

            if (vote._voteType == VoteType.Ownership) {
                voteOwnership(vote._voteId, vote._yeaPct, vote._nayPct);
            } else if (vote._voteType == VoteType.Parameter) {
                voteParameter(vote._voteId, vote._yeaPct, vote._nayPct);
            } else {
                revert WRONG_VOTE_TYPE();
            }
        }
    }

    /// @notice Vote for a ownership proposal
    /// @param _voteId The ID of the proposal
    /// @param _yeaPct Percent of votes in favor of the proposal
    /// @param _nayPct Percent of votes against the proposal
    /// @custom:throws NotAuthorized when the caller is not allowed
    function voteOwnership(uint256 _voteId, uint256 _yeaPct, uint256 _nayPct) public hasProposalsOrAllPermission {
        _votePercent(_voteId, _yeaPct, _nayPct, VOTER_OWNERSHIP);
    }

    /// @notice Vote for a parameter proposal
    /// @param _voteId The ID of the proposal
    /// @param _yeaPct Percent of votes in favor of the proposal
    /// @param _nayPct Percent of votes against the proposal
    /// @custom:throws NotAuthorized when the caller is not allowed
    function voteParameter(uint256 _voteId, uint256 _yeaPct, uint256 _nayPct) public hasProposalsOrAllPermission {
        _votePercent(_voteId, _yeaPct, _nayPct, VOTER_PARAMETER);
    }

    ////////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Vote for a proposal
    /// @param _voteId The ID of the proposal
    /// @param _yeaPct Percent of votes in favor of the proposal
    /// @param _nayPct Percent of votes against the proposal
    /// @param _voter The address of the voter
    /// @custom:throws WRONG_PCT when the pct is not valid
    function _votePercent(uint256 _voteId, uint256 _yeaPct, uint256 _nayPct, address _voter) internal {
        uint64 pctBase = IVoting(_voter).PCT_BASE();
        require(pctBase == (_yeaPct + _nayPct), WRONG_PCT());

        bytes memory data = abi.encodeWithSelector(IVoting.votePct.selector, _voteId, _yeaPct, _nayPct, false);
        _executeTransaction(_voter, data);
    }

    /// @notice Get the locker address
    /// @dev Must be implemented for the SafeModule contract
    function _getLocker() internal view override returns (address) {
        return LOCKER;
    }

    function _getController() internal view override returns (address) {
        return CONTROLLER;
    }
}
