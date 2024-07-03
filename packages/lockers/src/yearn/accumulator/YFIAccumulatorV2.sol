// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {Accumulator} from "src/base/accumulator/Accumulator.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IYearnStrategy} from "src/base/interfaces/IYearnStrategy.sol";

/// @title A contract that accumulates YFI and dYFI rewards and notifies them to the LGV4
/// @author StakeDAO
contract YFIAccumulatorV2 is Accumulator {
    /// @notice DFYI token address
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    /// @notice YFI token address
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;

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
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance) Accumulator(_gauge, DYFI, _locker, _governance) {
        strategy = 0x1be150a35bb8233d092747eBFDc75FB357c35168;
        ERC20(YFI).approve(_gauge, type(uint256).max);
        ERC20(DYFI).approve(_gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims YFI or DYFI rewards for the locker and notify all to the LGV4
    function claimTokenAndNotifyAll(address token, bool notifySDT, bool, bool claimFeeStrategy) external override {
        if (token != YFI && token != DYFI) revert WRONG_TOKEN();

        // Sending strategy fees to fee receiver
        if (claimFeeStrategy) {
            _claimFeeStrategy();
        }

        if (token == YFI) {
            // claim YFI reward
            IYearnStrategy(strategy).claimNativeRewards();
        } else {
            // claim dYFI reward
            IYearnStrategy(strategy).claimDYFIRewardPool();
        }
        uint256 amount = ERC20(token).balanceOf(address(this));

        // notify YFI or DYFI as reward in sdYFI gauge
        _notifyReward(token, amount, false);

        if (claimFeeStrategy) {
            _notifyReward(DYFI, 0, claimFeeStrategy);
        }

        if (notifySDT) {
            // notify SDT
            _distributeSDT();
        }
    }

    /// @notice Claims YFI and DYFI rewards for the locker and notify all to the LGV4
    function claimAndNotifyAll(bool _notifySDT, bool, bool claimFeeStrategy) external override {
        // claim YFI reward
        IYearnStrategy(strategy).claimNativeRewards();
        uint256 yfiAmount = ERC20(YFI).balanceOf(address(this));

        // claim dYFI reward
        IYearnStrategy(strategy).claimDYFIRewardPool();
        uint256 dYfiAmount = ERC20(DYFI).balanceOf(address(this));

        // Sending strategy fees to fee receiver
        if (claimFeeStrategy) {
            _claimFeeStrategy();
        }

        // notify YFI and DYFI as reward in sdYFI gauge
        _notifyReward(YFI, yfiAmount, false);
        _notifyReward(DYFI, dYfiAmount, claimFeeStrategy);

        if (_notifySDT) {
            // notify SDT
            _distributeSDT();
        }
    }
}
