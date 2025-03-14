// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IStrategy, IAllocator} from "src/interfaces/IStrategy.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";

contract MockStrategy is IStrategy {
    using TransientSlot for *;

    /// @dev Slot for the flush amount in transient storage
    bytes32 private constant FLUSH_AMOUNT_SLOT = keccak256("strategy.flush.amount");

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
        returns (PendingRewards memory _pendingRewards)
    {
        if (harvestData.length == 0) {
            return _pendingRewards;
        }

        (uint256 amount, uint256 randomSplit) = abi.decode(harvestData, (uint256, uint256));

        // Update flush amount in transient storage
        uint256 currentFlushAmount = FLUSH_AMOUNT_SLOT.asUint256().tload();
        FLUSH_AMOUNT_SLOT.asUint256().tstore(currentFlushAmount + amount);

        /// Calculate the fee subject amount.
        _pendingRewards.feeSubjectAmount = uint128(amount * 1e18 / randomSplit);
        _pendingRewards.totalAmount = uint128(amount);
    }

    function flush() external override {
        // Get flush amount from transient storage
        uint256 flushAmount = FLUSH_AMOUNT_SLOT.asUint256().tload();

        rewardToken.mint(msg.sender, flushAmount);

        // Reset the flush amount in transient storage
        FLUSH_AMOUNT_SLOT.asUint256().tstore(0);
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}
