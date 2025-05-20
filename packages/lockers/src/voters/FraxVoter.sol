// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {FraxLocker, FraxProtocol} from "address-book/src/FraxEthereum.sol";
import {BaseVoter} from "src/voters/BaseVoter.sol";

/// @title FraxVoter
/// @notice This contract manages all the voting related to Frax protocols
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract FraxVoter is BaseVoter {
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

    constructor(address _gateway) BaseVoter(_gateway) {}

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
