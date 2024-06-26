// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {ICakeNfpm} from "src/base/interfaces/ICakeNfpm.sol";

interface ICakeMc {
    struct UserPositionInfo {
        uint128 liquidity;
        uint128 boostLiquidity;
        int24 tickLower;
        int24 tickUpper;
        uint256 rewardGrowthInside;
        uint256 reward;
        address user;
        uint256 pid;
        uint256 boostMultiplier;
    }

    function userPositionInfos(uint256 _tokenId) external view returns (UserPositionInfo memory);

    function increaseLiquidity(ICakeNfpm.IncreaseLiquidityParams calldata params)
        external
        returns (uint256, uint256, uint256);
}
