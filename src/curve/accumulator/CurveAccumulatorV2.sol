// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IStrategy} from "herdaddy/interfaces/IStrategy.sol";
import {AccumulatorV2} from "src/base/accumulator/AccumulatorV2.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

/// @title A contract that accumulates 3crv rewards and notifies them to the LGV4
/// @author StakeDAO
contract CurveAccumulatorV2 is AccumulatorV2 {
    address public constant CRV3 = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice Curve strategy address
    IStrategy public immutable strategy = IStrategy(0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd);

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
        ERC20(CRV3).approve(_gauge, type(uint256).max);
        ERC20(CRV).approve(_gauge, type(uint256).max);
    }


    ////////////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    ////////////////////////////////////////////////////////////

    function claimAndNotifyAll(bool _notifySDT, bool _pullFromRewardSplitter, bool _distributeRewardsFromStrategy) external override {
        // Claim 3CRV rewards 
        strategy.claimNativeRewards();
        uint256 crv3Amount = ERC20(CRV3).balanceOf(address(this));

		uint256 crvAmount = ERC20(CRV).balanceOf(address(this));

        // Sending strategy fees to reward receiver
        if (_distributeRewardsFromStrategy) {
            _distributeFromStrategy(address(strategy));
        }

        // Notify 3CRV and CRV rewards
        _notifyReward(CRV3, crv3Amount, false);
        _notifyReward(CRV, crvAmount, _pullFromRewardSplitter);

        if (_notifySDT) {
            _distributeSDT();
        }

    }


    /// @notice Claims 3CRV or CRV rewards for the locker and notify all to the LGV4
    function claimTokenAndNotifyAll(address _token, bool _notifySDT, bool _pullFromRewardSplitter, bool _distributeRewardsFromStrategy) external override {
        if (_token != CRV3 && _token != CRV) revert WRONG_TOKEN();

        if (_token == CRV3) {
            // claim 3CRV reward
            strategy.claimNativeRewards();
        } 
        
        uint256 amount = ERC20(_token).balanceOf(address(this));

        // Sending strategy fees to reward receiver
        if (_distributeRewardsFromStrategy) {
            _distributeFromStrategy(address(strategy));
        }

        // notify 3CRV or CRV as reward in sdCRV gauge
        _notifyReward(_token, amount, _pullFromRewardSplitter);

        if (_notifySDT) {
            // notify SDT
            _distributeSDT();
        }
        
    }

}
