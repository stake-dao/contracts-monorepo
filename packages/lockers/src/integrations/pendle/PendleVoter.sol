// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PendleLocker} from "address-book/src/PendleEthereum.sol";
import {VoterBase} from "src/VoterBase.sol";

/// @title PendleVoter
/// @notice This contract manages all the voting related to Pendle protocols
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract PendleVoter is VoterBase {
    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice The address of the Pendle locker
    address public constant LOCKER = PendleLocker.LOCKER;

    /// @notice The address of the Pendle voting controller contract
    address public constant CONTROLLER = PendleLocker.VOTING_CONTROLLER;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when the given parameters have different lengths
    error WRONG_DATA();

    /// @param _gateway Address of the gateway contract
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _gateway) VoterBase(_gateway) {}

    ////////////////////////////////////////////////////////////////
    /// --- PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Bundle gauge votes with our strategy contract
    /// @param _gauges Gauges addresses
    /// @param _weights uint64 gauges weights
    /// @dev The `_gauges` and `_weights` parameters must have the same length
    /// @custom:throws WRONG_DATA if the `_gauges` and `_weights` parameters have different lengths
    function voteGauges(address[] calldata _gauges, uint64[] calldata _weights) external hasGaugesOrAllPermission {
        if (_gauges.length != _weights.length) revert WRONG_DATA();

        bytes memory votes_data = abi.encodeWithSignature("vote(address[],uint64[])", _gauges, _weights);
        _executeTransaction(CONTROLLER, votes_data);
    }

    /// @notice DEPRECATED: Use `voteGauges(address[],uint64[])` instead
    function voteGauges(address[] calldata, uint256[] calldata) external pure override {
        revert("NOT_IMPLEMENTED");
    }

    ////////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Get the locker address
    /// @dev Must be implemented for the SafeModule contract
    function _getLocker() internal pure override returns (address) {
        return LOCKER;
    }

    function _getController() internal pure override returns (address) {
        return CONTROLLER;
    }
}
