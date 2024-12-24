// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "src/interfaces/ISidecar.sol";

contract MockSidecar is ISidecar {
    IERC20 public asset;

    constructor(address asset_) {
        asset = IERC20(asset_);
    }

    function deposit(uint256 amount) external {
        // Implementation of the deposit function
    }

    function withdraw(uint256 amount, address receiver) external {
        // Implementation of the withdraw function
    }

    function balanceOf() external view returns (uint256) {
        // Implementation of the balanceOf function
    }

    function getPendingRewards() external view returns (uint256) {
        // Implementation of the getPendingRewards function
    }

    function getRewardTokens() external view returns (address[] memory) {
        // Implementation of the getRewardTokens function
    }

    function claim() external returns (uint256) {
        // Implementation of the claim function
    }
}
