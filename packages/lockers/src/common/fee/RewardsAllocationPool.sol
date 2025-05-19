// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/common/fee/Recipient.sol";

/// @title RewardsAllocationPool - Contract to receive SDT from Inflation and allocate them strategically for boostrapping purposes.
contract RewardsAllocationPool is Recipient {
    constructor(address _governance) Recipient(_governance) {}

    function name() external pure returns (string memory) {
        return "Rewards Allocation Pool";
    }
}
