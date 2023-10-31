// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title RewardReceiverSingleToken.
/// @dev Contract used only to receive the _rewardToken and approve the _strategy to transfer it.
contract RewardReceiverSingleToken {
    constructor(address _rewardToken, address _strategy) {
        SafeTransferLib.safeApproveWithRetry(_rewardToken, _strategy, type(uint256).max);
    }
}
