// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./governance/AllowanceManager.sol";
import "./interfaces/ISafe.sol";
import "./interfaces/ISafeOperation.sol";

contract GaugeVoter is AllowanceManager {

    /// @notice Stake DAO governance owner
    address public immutable SD_SAFE = address(0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765);
    
    // Pendle data
    address public immutable PENDLE_LOCKER = address(0xD8fa8dC5aDeC503AcC5e026a98F32Ca5C1Fa289A);
    address public immutable PENDLE_VOTER = address(0x44087E105137a5095c008AaB6a6530182821F2F0);
    address public immutable PENDLE_STRATEGY = address(0xA7641acBc1E85A7eD70ea7bCFFB91afb12AD0c54);

    /// @notice Voter contracts allowed
    mapping(address => bool) public VOTERS_ALLOWED;

    constructor() AllowanceManager(msg.sender) {

    }

    /// @notice Bundle gauge votes, _gauges and _weights must have the same length
    /// @param _voter A voter address allowed with toggle_voter(_voter, true)
    /// @param _gauges Array of gauge addresses
    /// @param _weights Array of weights
    function vote_with_voter(address _voter, address[] calldata _gauges, uint256[] calldata _weights) external onlyGovernanceOrAllowed {
        if(!VOTERS_ALLOWED[_voter]) {
            revert VOTER_NOT_ALLOW();
        }

        if(_gauges.length != _weights.length) {
            revert WRONG_DATA();
        }

        bytes memory data = abi.encodeWithSignature("voteGauges(address[],uint256[])", _gauges, _weights);
        require(ISafe(SD_SAFE).execTransactionFromModule(_voter, 0, data, ISafeOperation.Call), "Could not execute vote");
    }

    /// @notice Bundle gauge votes with our strategy contract, _gauges and _weights must have the same length
    /// @param _gauges Array of gauge addresses
    /// @param _weights Array of weights
    function vote_pendle(address[] calldata _gauges, uint64[] calldata _weights) external onlyGovernanceOrAllowed {
        if(_gauges.length != _weights.length) {
            revert WRONG_DATA();
        }

        bytes memory votes_data = abi.encodeWithSignature("vote(address[],uint64[])", _gauges, _weights);
        bytes memory voter_data = abi.encodeWithSignature("execute(address,uint256,bytes)", PENDLE_VOTER, 0, votes_data);
        bytes memory locker_data = abi.encodeWithSignature("execute(address,uint256,bytes)", PENDLE_LOCKER, 0, voter_data);
        require(ISafe(SD_SAFE).execTransactionFromModule(PENDLE_STRATEGY, 0, locker_data, ISafeOperation.Call), "Could not execute vote");
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