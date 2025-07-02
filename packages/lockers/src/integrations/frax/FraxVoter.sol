// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {FraxLocker, FraxProtocol} from "@address-book/src/FraxEthereum.sol";
import {VoterBase} from "src/VoterBase.sol";

/// @title FraxVoter
/// @notice This contract manages all the voting related to Frax protocols
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract FraxVoter is VoterBase {
    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Frax locker
    address public immutable LOCKER = FraxLocker.LOCKER;

    /// @notice Frax gauge controller
    address public immutable CONTROLLER = FraxProtocol.GAUGE_CONTROLLER;

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
