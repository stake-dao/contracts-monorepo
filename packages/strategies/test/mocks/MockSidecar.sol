// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "src/interfaces/ISidecar.sol";
import "test/mocks/ITokenMinter.sol";

contract MockSidecar is ISidecar {
    IERC20 public asset;
    address public accountant;
    ITokenMinter public rewardToken;

    constructor(address asset_, address rewardToken_, address accountant_) {
        asset = IERC20(asset_);
        rewardToken = ITokenMinter(rewardToken_);
        accountant = accountant_;
    }

    error DepositFailed();

    function deposit(uint256 amount) external view {
        require(asset.balanceOf(address(this)) >= amount, DepositFailed());
    }

    function withdraw(uint256 amount, address receiver) external {
        asset.transfer(receiver, amount);
    }

    function balanceOf() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function getPendingRewards() public view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    function getRewardTokens() external view returns (address[] memory) {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(rewardToken);
        return rewardTokens;
    }

    function claim() external returns (uint256 pendingRewards) {
        pendingRewards = getPendingRewards();
        rewardToken.transfer(accountant, pendingRewards);
    }
}
