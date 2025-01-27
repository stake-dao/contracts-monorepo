// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/fee/Recipient.sol";

/// @title StakeDao Locker Rewards Recipient - Contract to receive StakeDao Locker rewards (from Votemarket)
contract StakeDaoLockerRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}

    function name() external pure returns (string memory) {
        return "Votemarket StakeDao Locker Rewards Recipient";
    }
}
