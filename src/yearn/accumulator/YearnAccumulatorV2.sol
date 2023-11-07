// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import {IYearnStrategy} from "src/base/interfaces/IYearnStrategy.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {Accumulator} from "src/base/accumulator/Accumulator.sol";

/// @title A contract that accumulates YFI and dYFI rewards and notifies them to the LGV4
/// @author StakeDAO
contract YearnAccumulatorV2 is Accumulator {
    error WRONG_TOKEN();

    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;

    IYearnStrategy public immutable strategy;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        address _gauge,
        address _locker,
        address _daoFeeRecipient,
        address _liquidityFeeRecipient,
        address _strategy
    ) Accumulator(_gauge, _locker, _daoFeeRecipient, _liquidityFeeRecipient) {
        strategy = IYearnStrategy(_strategy);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /// @notice Claims YFI or DYFI rewards for the locker and notify all to the LGV4
    function claimSingleTokenAndNotifyAll(address _token) external override {
        if (_token != YFI && _token != DYFI) revert WRONG_TOKEN();

        if (_token == YFI) {
            strategy.claimNativeRewards();
        } else {
            strategy.claimDYFIRewardPool();
        }
        uint256 amount = ERC20(_token).balanceOf(address(this));
        // charge fees
        amount -= _chargeFee(_token, amount);
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

        yfiAmount -= _chargeFee(YFI, yfiAmount);
        dYfiAmount -= _chargeFee(DYFI, dYfiAmount);

        _notifyReward(YFI, yfiAmount);
        _notifyReward(DYFI, dYfiAmount);

        _distributeSDT();
    }
}
