// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IStrategy, IAllocator} from "src/interfaces/IStrategy.sol";

contract MockStrategy is IStrategy {
    ERC20Mock public immutable rewardToken;

    constructor(address rewardToken_) {
        rewardToken = ERC20Mock(rewardToken_);
    }

    function deposit(IAllocator.Allocation memory) external pure override returns (PendingRewards memory) {
        return PendingRewards({feeSubjectAmount: 0, totalAmount: 0});
    }

    function withdraw(IAllocator.Allocation memory) external pure returns (PendingRewards memory) {
        return PendingRewards({feeSubjectAmount: 0, totalAmount: 0});
    }

    function pendingRewards(address) external pure returns (PendingRewards memory) {
        return PendingRewards({feeSubjectAmount: 0, totalAmount: 0});
    }

    function harvest(address, bytes memory harvestData)
        external
        override
        returns (PendingRewards memory pendingRewards)
    {
        if (harvestData.length == 0) {
            return pendingRewards;
        }

        (uint256 amount, uint256 randomSplit) = abi.decode(harvestData, (uint256, uint256));

        rewardToken.mint(msg.sender, amount);

        /// Calculate the fee subject amount.
        pendingRewards.feeSubjectAmount = uint128(amount * 1e18 / randomSplit);
        pendingRewards.totalAmount = uint128(amount);
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}
