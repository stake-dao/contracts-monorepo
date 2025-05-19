// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "src/common/fee/Recipient.sol";

/// @title VotersRewardsRecipient - Contract to receive voters rewards before distributing them to the voters as sdPendle.
contract VotersRewardsRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}
}
