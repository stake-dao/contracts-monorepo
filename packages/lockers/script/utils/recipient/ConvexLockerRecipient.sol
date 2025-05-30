// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/Recipient.sol";

/// @title Convex Locker Rewards Recipient - Contract to receive Convex Locker rewards (from Votemarket)
contract ConvexLockerRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}

    function name() external pure returns (string memory) {
        return "Votemarket Convex Locker Rewards Recipient";
    }
}
