// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/fee/Recipient.sol";

/// @title VeSDTRecipient - Contract to receive Accrued Revenues to distribute to VeSDT holders.
contract VeSDTRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}
}
