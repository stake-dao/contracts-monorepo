/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISidecar {
    function balanceOf() external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount, address receiver) external;
    function getPendingRewards() external view returns (uint256);
    function getRewardTokens() external view returns (address[] memory);

    function claim() external returns (uint256);

    function asset() external view returns (IERC20);
}
