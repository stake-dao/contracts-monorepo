// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/common/fee/Recipient.sol";

/// @title TreasuryRecipient - Contract to receive accrued treasury fees.
contract TreasuryRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}
}
