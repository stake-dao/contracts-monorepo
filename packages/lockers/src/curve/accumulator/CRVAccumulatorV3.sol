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

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when a token not supported is used
    error WRONG_TOKEN();

    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    constructor(address _gauge, address _locker, address _governance)
        AccumulatorV2(_gauge, CRV_USD, _locker, _governance)
    {
        strategy = 0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd;
        SafeTransferLib.safeApprove(CRV, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(CRV_USD, _gauge, type(uint256).max);
    }

    ////////////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    ////////////////////////////////////////////////////////////

    function claimAndNotifyAll(bool notifySDT, bool, bool claimFeeStrategy) external override {
        /// Claim CRVUSD rewards.
        IStrategy(strategy).claimNativeRewards();

        // Claim Extra CRV rewards.
        if (claimFeeStrategy) {
            _claimFeeStrategy();
        }

        notifyReward(CRV_USD, false, false);
        notifyReward(CRV, notifySDT, claimFeeStrategy);
    }
}
