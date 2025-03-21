// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "address-book/src/dao/1.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";

abstract contract CommonBase {
    address public locker;
    address public sdToken;
    address public veToken;

    ERC20 public rewardToken;
    ERC20 public strategyRewardToken;

    ILiquidityGauge public liquidityGauge;

    BaseAccumulator public accumulator;

    IDepositor public depositor;

    address public treasuryRecipient = DAO.TREASURY;
    address public liquidityFeeRecipient = DAO.LIQUIDITY_FEES_RECIPIENT;

    constructor() {}
}
