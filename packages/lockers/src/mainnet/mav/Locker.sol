// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {VeMAVLocker} from "src/common/locker/VeMAVLocker.sol";

/// @title  Locker
/// @notice Locker contract for locking tokens for a period of time
/// @dev Adapted for Maverick Voting Escrow.
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract Locker is VeMAVLocker {
    constructor(address _governance, address _token, address _veToken) VeMAVLocker(_governance, _token, _veToken) {}

    function name() public pure override returns (string memory) {
        return "MAV Locker";
    }
}
