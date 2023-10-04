// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IVotingEscrowMav} from "src/base/interfaces/IVotingEscrowMav.sol";
import {VeMAVLocker} from "src/base/locker/VeMAVLocker.sol";

/// @title  MAVLocker
/// @notice Locker contract for locking tokens for a period of time
/// @dev Adapted for Maverick Voting Escrow.
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract MAVLocker is VeMAVLocker {
    constructor(address _governance, address _token, address _veToken) VeMAVLocker(_governance, _token, _veToken) {}

    function name() public pure override returns (string memory) {
        return "MAV Locker";
    }
}