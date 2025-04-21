// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRewardReceiver {
    function distributeRewards() external;
    function distributeRewardToken(IERC20 token) external;
}
