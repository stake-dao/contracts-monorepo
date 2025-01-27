// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/fee/Recipient.sol";

/// @title Convex Locker Rewards Recipient - Contract to receive Convex Locker rewards (from Votemarket)
contract ConvexLockerRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}

    function name() external pure returns (string memory) {
        return "Votemarket Convex Locker Rewards Recipient";
    }
}
