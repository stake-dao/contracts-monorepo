// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/common/fee/Recipient.sol";

/// @title LiquidityFeeRecipient - Contract to receive Accrued Liquidity Fees to refuel SdToken vote bounties.
contract LiquidityFeeRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}
}
