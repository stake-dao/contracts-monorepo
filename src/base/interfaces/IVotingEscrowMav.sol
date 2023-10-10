// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVotingEscrowMav {
    function lockupCount(address staker) external view returns (uint256 count);
    function previewPoints(uint256 amount, uint256 duration) external view returns (uint256, uint256);

    function stake(uint256 amount, uint256 duration, address to) external;
    function stake(uint256 amount, uint256 duration, bool doDelegation) external;

    function unstake(uint256 lockupId) external;

    function extend(uint256 lockupId, uint256 duration, uint256 amount, bool doDelegation) external;

    function balanceOf(address account) external view returns (uint256);
}
