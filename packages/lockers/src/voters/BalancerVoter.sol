// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {BalancerLocker, BalancerProtocol} from "address-book/src/BalancerEthereum.sol";
import {BaseVoter} from "src/voters/BaseVoter.sol";

/// @title BalancerVoter
/// @notice This contract manages all the voting related to Balancer protocols
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract BalancerVoter is BaseVoter {
    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Balancer locker
    address public immutable LOCKER = BalancerLocker.LOCKER;

    /// @notice Balancer gauge controller
    address public immutable CONTROLLER = BalancerProtocol.GAUGE_CONTROLLER;

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
