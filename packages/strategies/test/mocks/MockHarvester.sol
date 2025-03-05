// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IHarvester} from "src/interfaces/IHarvester.sol";

contract MockHarvester is IHarvester {
    ERC20Mock public immutable rewardToken;

    constructor(address rewardToken_) {
        rewardToken = ERC20Mock(rewardToken_);
    }

    function harvest(address, bytes memory harvestData)
        external
        override
        returns (IStrategy.PendingRewards memory pendingRewards)
    {
        if (harvestData.length == 0) {
            return pendingRewards;
        }

        (uint256 amount, uint256 randomSplit) = abi.decode(harvestData, (uint256, uint256));

        rewardToken.mint(address(this), amount);

        /// Calculate the fee subject amount.
        pendingRewards.feeSubjectAmount = uint128(amount * 1e18 / randomSplit);
        pendingRewards.totalAmount = uint128(amount);
    }
}
