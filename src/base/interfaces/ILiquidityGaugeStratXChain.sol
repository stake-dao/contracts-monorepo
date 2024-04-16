// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ILiquidityGaugeStratXChain {
    function add_reward(address _rewardToken, address _distributor) external;

    function commit_transfer_ownership(address _newOwner) external;

    function initialize(address _stakingToken, address _admin, address _vault, string memory _symbol) external;
}
