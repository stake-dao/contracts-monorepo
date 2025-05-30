// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/Recipient.sol";

/// @title StakeDao Locker Rewards Recipient - Contract to receive StakeDao Locker rewards (from Votemarket)
contract StakeDaoLockerRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}

    function name() external pure returns (string memory) {
        return "Votemarket StakeDao Locker Rewards Recipient";
    }
}
