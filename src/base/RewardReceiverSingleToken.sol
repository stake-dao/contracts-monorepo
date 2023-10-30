// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/**
 * @title RewardReceiverSingleToken
 * @dev Contract used only to receive the _rewardToken and approve the _strategy to transfer it
 */
contract RewardReceiverSingleToken {
    constructor(address _rewardToken, address _strategy) {
        IERC20(_rewardToken).approve(_strategy, type(uint256).max);
    }
}
