// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IVotingEscrowMav} from "src/common/interfaces/IVotingEscrowMav.sol";
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
