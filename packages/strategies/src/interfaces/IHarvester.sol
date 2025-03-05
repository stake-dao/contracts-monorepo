// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IStrategy} from "src/interfaces/IStrategy.sol";

interface IHarvester {
    function harvest(address gauge, bytes calldata extraData)
        external
        returns (IStrategy.PendingRewards memory pendingRewards);
}
