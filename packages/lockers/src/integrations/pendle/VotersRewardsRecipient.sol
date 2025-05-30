// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/Recipient.sol";

/// @title VotersRewardsRecipient - Contract to receive voters rewards before distributing them to the voters as sdPendle.
contract VotersRewardsRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}
}
