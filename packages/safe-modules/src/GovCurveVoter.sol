// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./governance/AllowanceManager.sol";

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

import "./interfaces/ISafe.sol";
import "./interfaces/ISafeOperation.sol";

enum VoterState {
    Absent,
    Yea,
    Nay,
    Even
}

interface ICurveVoter {
    function PCT_BASE() external view returns (uint64);
    function getVoterState(uint256 _voteId, address _voter) external view returns (VoterState);
}

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

contract GovCurveVoter is AllowanceManager {
    using FixedPointMathLib for uint256;

    /// @notice Curve voter for ownership proposals
    address public immutable VOTER_OWNERSHIP = address(0xE478de485ad2fe566d49342Cbd03E49ed7DB3356);

    /// @notice Curve voter for parameter proposals
    address public immutable VOTER_PARAMETER = address(0xBCfF8B0b9419b9A88c44546519b1e909cF330399);

    /// @notice Stake DAO Curve voter
    address public immutable SD_VOTER = address(0x20b22019406Cf990F0569a6161cf30B8e6651dDa);

    /// @notice Stake DAO governance owner
    address public immutable SD_SAFE = address(0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765);

    constructor() AllowanceManager(msg.sender) {}

    /// @notice Bundle ownershipt and/or parameter votes
    /// @dev Can be called only by someone allowed
    /// @dev VoteType 0 = Ownership / 1 = Parameter
    function votes(Vote[] calldata _votes) external onlyGovernanceOrAllowed {
        uint256 length = _votes.length;
        for (uint256 i = 0; i < length; i++) {
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
    /// @dev Can be called only by someone allowed
    function voteOwnership(uint256 _voteId, uint256 _yeaPct, uint256 _nayPct) public onlyGovernanceOrAllowed {
        _vote(_voteId, _yeaPct, _nayPct, VOTER_OWNERSHIP);
    }

    /// @notice Vote for a parameter proposal
    /// @dev Can be called only by someone allowed
    function voteParameter(uint256 _voteId, uint256 _yeaPct, uint256 _nayPct) public onlyGovernanceOrAllowed {
        _vote(_voteId, _yeaPct, _nayPct, VOTER_PARAMETER);
    }

    function _vote(uint256 _voteId, uint256 _yeaPct, uint256 _nayPct, address _voter) internal {
        uint64 pctBase = ICurveVoter(_voter).PCT_BASE();
        if (pctBase != (_yeaPct + _nayPct)) revert WRONG_PCT();

        bytes memory data =
            abi.encodeWithSignature("votePct(uint256,uint256,uint256,address)", _voteId, _yeaPct, _nayPct, _voter);
        require(
            ISafe(SD_SAFE).execTransactionFromModule(SD_VOTER, 0, data, ISafeOperation.Call), "Could not execute vote"
        );
    }

    ////////////////////////////////////////////////////////////////
    // --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when pct is different than voter pct
    error WRONG_PCT();

    /// @notice Error emitted when we try to vote for something else than Ownership or Parameter
    error WRONG_VOTE_TYPE();
}
