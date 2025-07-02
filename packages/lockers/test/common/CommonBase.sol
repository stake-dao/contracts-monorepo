// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {DAO} from "@address-book/src/DaoEthereum.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {IDepositor} from "src/interfaces/IDepositor.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";

abstract contract CommonBase {
    address public locker;
    address public sdToken;
    address public veToken;

    ERC20 public rewardToken;
    ERC20 public strategyRewardToken;

    ILiquidityGauge public liquidityGauge;

    AccumulatorBase public accumulator;

    IDepositor public depositor;

    address public treasuryRecipient = DAO.TREASURY;
    address public liquidityFeeRecipient = DAO.LIQUIDITY_FEES_RECIPIENT;

    constructor() {}
}
