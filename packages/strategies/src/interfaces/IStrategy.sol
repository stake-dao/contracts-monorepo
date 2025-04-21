// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/interfaces/IAllocator.sol";

interface IStrategy {
    struct PendingRewards {
        uint128 feeSubjectAmount;
        uint128 totalAmount;
    }

    function deposit(IAllocator.Allocation calldata allocation, bool harvest)
        external
        returns (PendingRewards memory pendingRewards);
    function withdraw(IAllocator.Allocation calldata allocation, bool harvest, address receiver)
        external
        returns (PendingRewards memory pendingRewards);

    function balanceOf(address gauge) external view returns (uint256 balance);

    function harvest(address gauge, bytes calldata extraData) external returns (PendingRewards memory pendingRewards);
    function flush() external;
}
