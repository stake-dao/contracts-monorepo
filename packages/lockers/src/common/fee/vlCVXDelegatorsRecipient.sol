// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/fee/Recipient.sol";

/// @title VlCVX Delegators Rewards Recipient - Contract to receive vlCVX rewards that has to be distributed to delegators (from Votemarket)
contract VlCVXDelegatorsRecipient is Recipient {
    constructor(address _governance) Recipient(_governance) {}

    function name() external pure returns (string memory) {
        return "Votemarket VlCVX Delegators Rewards Recipient";
    }
}
