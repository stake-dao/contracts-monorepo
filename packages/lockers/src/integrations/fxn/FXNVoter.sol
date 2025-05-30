// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {FXNLocker, FXNProtocol} from "address-book/src/FXNEthereum.sol";
import {VoterBase} from "src/VoterBase.sol";

/// @title FXNVoter
/// @notice This contract manages all the voting related to FXN protocols
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract FXNVoter is VoterBase {
    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Address of the cake locker
    address public immutable LOCKER = FXNLocker.LOCKER;

    /// @notice Address of the pancake gauge controller
    address public immutable CONTROLLER = FXNProtocol.GAUGE_CONTROLLER;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    constructor(address _gateway) VoterBase(_gateway) {}

    ////////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Get the locker address
    /// @dev Must be implemented for the SafeModule contract
    function _getLocker() internal view override returns (address) {
        return LOCKER;
    }

    function _getController() internal view override returns (address) {
        return CONTROLLER;
    }
}
