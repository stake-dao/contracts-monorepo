// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IStrategy} from "herdaddy/interfaces/IStrategy.sol";
import {AccumulatorV2} from "src/base/accumulator/AccumulatorV2.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

/// @title A contract that accumulates crvUsd rewards and notifies them to the LGV4
/// @author StakeDAO
contract CurveAccumulatorV3 is AccumulatorV2 {
    address public constant CRV_USD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice Curve strategy address
    IStrategy public constant STRATEGY = IStrategy(0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd);

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when a token not supported is used
    error WRONG_TOKEN();

    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    constructor(
        address _gauge,
        address _locker,
        address _daoFeeRecipient,
        address _liquidityFeeRecipient,
        address _governance
    ) AccumulatorV2(_gauge, _locker, _daoFeeRecipient, _liquidityFeeRecipient, _governance) {
        ERC20(CRV_USD).approve(_gauge, type(uint256).max);
        ERC20(CRV).approve(_gauge, type(uint256).max);
    }

    ////////////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    ////////////////////////////////////////////////////////////

    function claimAndNotifyAll(bool _notifySDT, bool _pullFromFeeReceiver, bool sendFeeStrategyReceiver)
        external
        override
    {
        // Claim CRVUSD rewards
        STRATEGY.claimNativeRewards();
        uint256 crvUsdAmount = ERC20(CRV_USD).balanceOf(address(this));

        uint256 crvAmount = ERC20(CRV).balanceOf(address(this));

        // Sending strategy fees to fee receiver
        if (sendFeeStrategyReceiver) {
            _sendFeeStrategyReceiver(address(STRATEGY));
        }

        // Notify CRVUSD and CRV rewards
        _notifyReward(CRV_USD, crvUsdAmount, false);
        _notifyReward(CRV, crvAmount, _pullFromFeeReceiver);

        if (_notifySDT) {
            _distributeSDT();
        }
    }

    /// @notice Claims CRVUSD or CRV rewards for the locker and notify all to the LGV4
    function claimTokenAndNotifyAll(
        address _token,
        bool _notifySDT,
        bool _pullFromFeeReceiver,
        bool sendFeeStrategyReceiver
    ) external override {
        if (_token != CRV_USD && _token != CRV) revert WRONG_TOKEN();

        if (_token == CRV_USD) {
            // claim CRV_USD reward
            STRATEGY.claimNativeRewards();
        }

        uint256 amount = ERC20(_token).balanceOf(address(this));

        // Sending strategy fees to fee receiver
        if (sendFeeStrategyReceiver) {
            _sendFeeStrategyReceiver(address(STRATEGY));
        }

        // notify CRV_USD or CRV as reward in sdCRV gauge
        _notifyReward(_token, amount, _pullFromFeeReceiver);

        if (_notifySDT) {
            // notify SDT
            _distributeSDT();
        }
    }
}