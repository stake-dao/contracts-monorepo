// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Governance} from "common/governance/Governance.sol";
import {IVoter} from "src/interfaces/IVoter.sol";
import {VoterPermissionManager} from "src/VoterPermissionManager.sol";

/// @title VoteGaugeRouter
/// @notice This contract serves as an unique entry point to vote on gauges for multiple voters
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract VoteGaugeRouter is Governance {
    /// @notice Error emitted when the given parameters have different lengths
    error INCORRECT_LENGTH();

    /// @notice Error emitted when the given address is a zero address
    error ZERO_ADDRESS();

    constructor(address _governance) Governance(_governance) {}

    /// @notice Vote on gauges for a given voter
    /// @param _voter The address of the voter
    /// @param _gauges The addresses of the gauges to vote on
    /// @param _weights The weights to vote on
    /// @dev This contract must have the required permissions to call the `voteGauges` function on the given voter
    /// @custom:throws INCORRECT_LENGTH if the given parameters have different lengths
    /// @custom:throws ZERO_ADDRESS if the given address is a zero address
    function voteGauges(address _voter, address[] calldata _gauges, uint256[] calldata _weights)
        external
        onlyGovernance
    {
        require(_voter != address(0), ZERO_ADDRESS());
        require(_gauges.length == _weights.length, INCORRECT_LENGTH());

        IVoter(_voter).voteGauges(_gauges, _weights);
    }

    /// @notice Check if the given address has the required permissions to vote on gauges for the given voter
    /// @param _voter The address of the voter
    /// @return True if the given address has the required permissions, false otherwise
    function hasPermission(address _voter) external view returns (bool) {
        VoterPermissionManager.Permission permission = IVoter(_voter).getPermission(address(this));

        return permission == VoterPermissionManager.Permission.GAUGES_ONLY
            || permission == VoterPermissionManager.Permission.ALL;
    }
}
