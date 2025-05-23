// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IGaugeController} from "@interfaces/curve/IGaugeController.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";
import {VoterPermissionManager} from "src/voters/utils/VoterPermissionManager.sol";

/// @title BaseVoter
/// @notice This contract is the base contract for all the voting related to the different protocols
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
abstract contract BaseVoter is VoterPermissionManager, SafeModule {
    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when the length of the gauges and weights are not the same
    error INCORRECT_LENGTH();

    constructor(address gateway) VoterPermissionManager(msg.sender) SafeModule(gateway) {}

    ////////////////////////////////////////////////////////////////
    /// --- PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function voteGauges(address[] calldata _gauges, uint256[] calldata _weights)
        external
        virtual
        hasGaugesOrAllPermission
    {
        require(_gauges.length == _weights.length, INCORRECT_LENGTH());

        for (uint256 i; i < _gauges.length; i++) {
            bytes memory voteData =
                abi.encodeWithSelector(IGaugeController.vote_for_gauge_weights.selector, _gauges[i], _weights[i]);

            _executeTransaction(_getController(), voteData);
        }
    }

    ////////////////////////////////////////////////////////////////
    /// --- VIRTUAL FUNCTIONS -- MUST BE IMPLEMENTED
    ///////////////////////////////////////////////////////////////

    function _getController() internal view virtual returns (address);
    function _getLocker() internal view virtual override returns (address);
}
