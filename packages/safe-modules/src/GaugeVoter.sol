// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {PendleLocker} from "address-book/src/PendleEthereum.sol";
import {AllowanceManager} from "./governance/AllowanceManager.sol";
import {ISafe} from "./interfaces/ISafe.sol";
import {ISafeOperation} from "./interfaces/ISafeOperation.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";

contract GaugeVoter is AllowanceManager {
    /// @notice Stake DAO governance owner
    address public immutable SD_SAFE = address(DAO.GOVERNANCE);

    // Pendle data
    address public immutable PENDLE_LOCKER = address(PendleLocker.LOCKER);
    address public immutable PENDLE_VOTER = address(PendleLocker.VOTER);
    address public immutable PENDLE_STRATEGY = address(PendleLocker.STRATEGY);

    /// @notice Voter contracts allowed
    mapping(address => bool) public VOTERS_ALLOWED;

    constructor() AllowanceManager(msg.sender) {}

    /// @notice Bundle gauge votes, _gauges and _weights must have the same length
    /// @param _voter A voter address allowed with toggle_voter(_voter, true)
    /// @param _gauges Array of gauge addresses
    /// @param _weights Array of weights
    function vote_with_voter(address _voter, address[] calldata _gauges, uint256[] calldata _weights)
        external
        onlyGovernanceOrAllowed
    {
        if (!VOTERS_ALLOWED[_voter]) {
            revert VOTER_NOT_ALLOW();
        }

        if (_gauges.length != _weights.length) {
            revert WRONG_DATA();
        }

        bytes memory data = abi.encodeWithSignature("voteGauges(address[],uint256[])", _gauges, _weights);
        require(
            ISafe(SD_SAFE).execTransactionFromModule(_voter, 0, data, ISafeOperation.Call), "Could not execute vote"
        );
    }

    /// @notice Bundle gauge votes with our strategy contract, _gauges and _weights must have the same length
    /// @param _gauges Array of gauge addresses
    /// @param _weights Array of weights
    function vote_pendle(address[] calldata _gauges, uint64[] calldata _weights) external onlyGovernanceOrAllowed {
        if (_gauges.length != _weights.length) {
            revert WRONG_DATA();
        }

        bytes memory votes_data = abi.encodeWithSignature("vote(address[],uint64[])", _gauges, _weights);
        bytes memory voter_data = abi.encodeWithSignature("execute(address,uint256,bytes)", PENDLE_VOTER, 0, votes_data);
        bytes memory locker_data =
            abi.encodeWithSignature("execute(address,uint256,bytes)", PENDLE_LOCKER, 0, voter_data);
        require(
            ISafe(SD_SAFE).execTransactionFromModule(PENDLE_STRATEGY, 0, locker_data, ISafeOperation.Call),
            "Could not execute vote"
        );
    }

    /// @notice Allow or disallow a voter
    /// @param _voter Voter address
    /// @param _allow True to allow the voter to exec a gauge vote, False to disallow it
    function toggle_voter(address _voter, bool _allow) external onlyGovernanceOrAllowed {
        VOTERS_ALLOWED[_voter] = _allow;
    }

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when we try to vote with a voter which is not allowed
    error VOTER_NOT_ALLOW();

    /// @notice Error emitted when we try to vote with gauges length different than weights length
    error WRONG_DATA();
}
