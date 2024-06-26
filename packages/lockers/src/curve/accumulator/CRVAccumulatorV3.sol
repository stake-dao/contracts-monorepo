// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/accumulator/AccumulatorV2.sol";
import {IStrategy} from "herdaddy/interfaces/stake-dao/IStrategy.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

/// @title A contract that accumulates crvUsd rewards and notifies them to the LGV4
/// @author StakeDAO
contract CRVAccumulatorV3 is AccumulatorV2 {
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CRV_USD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

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

    constructor(address _gauge, address _locker, address _governance) AccumulatorV2(_gauge, _locker, _governance) {
        SafeTransferLib.safeApprove(CRV, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(CRV_USD, _gauge, type(uint256).max);
    }

    ////////////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    ////////////////////////////////////////////////////////////

    function claimAndNotifyAll(bool notifySDT, bool pullFromFeeReceiver, bool claimFeeStrategy) external override {
        /// Claim CRVUSD rewards.
        STRATEGY.claimNativeRewards();

        // Claim Extra CRV rewards.
        if (claimFeeStrategy) {
            _claimFeeStrategy(address(STRATEGY));
        }

        uint256 _balance = ERC20(CRV_USD).balanceOf(address(this));

        /// Notify CRVUSD and CRV rewards.
        _notifyReward(CRV_USD, _balance, false);

        /// We put 0 to avoid charging fees on CRV rewards.
        _notifyReward(CRV, 0, pullFromFeeReceiver);

        if (notifySDT) {
            _distributeSDT();
        }
    }

    function _notifyReward(address _tokenReward, uint256 _amount, bool _pullFromFeeReceiver) internal override {
        if (_tokenReward == CRV_USD) {
            _chargeFee(_tokenReward, _amount);
        }

        if (_pullFromFeeReceiver && feeReceiver != address(0)) {
            // Split fees for the specified token using the fee receiver contract
            // Function not permissionless, to prevent sending to that accumulator and re-splitting (_chargeFee)
            IFeeReceiver(feeReceiver).split(_tokenReward);
        }

        _amount = ERC20(_tokenReward).balanceOf(address(this));

        if (_amount == 0) return;
        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);
    }
}
