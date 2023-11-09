// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Accumulator} from "src/base/accumulator/Accumulator.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IYearnStrategy} from "src/base/interfaces/IYearnStrategy.sol";

/// @title A contract that accumulates YFI and dYFI rewards and notifies them to the LGV4
/// @author StakeDAO
contract YearnAccumulatorV2 is Accumulator {
    /// @notice DFYI token address
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    /// @notice YFI token address
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;

    /// @notice yearn strategy address
    IYearnStrategy public immutable strategy;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when a token not supported is used
    error WRONG_TOKEN();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _daoFeeRecipient dao fee recipient
    /// @param _liquidityFeeRecipient liquidity fee recipient
    /// @param _strategy strategy
    /// @param _governance governance
    constructor(
        address _gauge,
        address _locker,
        address _daoFeeRecipient,
        address _liquidityFeeRecipient,
        address _strategy,
        address _governance
    ) Accumulator(_gauge, _locker, _daoFeeRecipient, _liquidityFeeRecipient, _governance) {
        strategy = IYearnStrategy(_strategy);
        ERC20(YFI).approve(_gauge, type(uint256).max);
        ERC20(DYFI).approve(_gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims YFI or DYFI rewards for the locker and notify all to the LGV4
    function claimTokenAndNotifyAll(address _token) external override {
        if (_token != YFI && _token != DYFI) revert WRONG_TOKEN();

        if (_token == YFI) {
            // claim YFI reward
            strategy.claimNativeRewards();
        } else {
            // claim dYFI reward
            strategy.claimDYFIRewardPool();
        }
        uint256 amount = ERC20(_token).balanceOf(address(this));

        // notify YFI or DYFI as reward in sdYFI gauge
        _notifyReward(_token, amount);

        // notify SDT
        _distributeSDT();
    }

    /// @notice Claims YFI and DYFI rewards for the locker and notify all to the LGV4
    function claimAndNotifyAll() external override {
        // claim YFI reward
        strategy.claimNativeRewards();
        uint256 yfiAmount = ERC20(YFI).balanceOf(address(this));

        // claim dYFI reward
        strategy.claimDYFIRewardPool();
        uint256 dYfiAmount = ERC20(DYFI).balanceOf(address(this));

        // notify YFI and DYFI as reward in sdYFI gauge
        _notifyReward(YFI, yfiAmount);
        _notifyReward(DYFI, dYfiAmount);

        // notify SDT
        _distributeSDT();
    }

    /// @notice Notify the new reward to the LGV4
    /// @param _tokenReward token to notify
    /// @param _amount amount to notify
    function _notifyReward(address _tokenReward, uint256 _amount) internal override {
        if (_amount == 0) {
            return;
        }
        // charge fees
        _amount -= _chargeFee(_tokenReward, _amount);
        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);

        emit RewardNotified(gauge, _tokenReward, _amount);
    }
}
