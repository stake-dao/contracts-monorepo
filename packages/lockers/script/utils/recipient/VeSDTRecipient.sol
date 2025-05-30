// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/Recipient.sol";

/// @title VeSDTRecipient - Contract to receive Accrued Revenues to distribute to VeSDT holders.
contract VeSDTRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}
}
