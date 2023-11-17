// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Accumulator} from "src/base/accumulator/Accumulator.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ICakeLocker} from "src/base/interfaces/ICakeLocker.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IYearnStrategy} from "src/base/interfaces/IYearnStrategy.sol";

/// @title A contract that accumulates CAKE rewards and notifies them to the sdCAKE gauge
/// @author StakeDAO
contract CakeAccumulator is Accumulator {

    /// @notice CAKE token address
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _daoFeeRecipient dao fee recipient
    /// @param _liquidityFeeRecipient liquidity fee recipient
    /// @param _governance governance
    constructor(
        address _gauge,
        address _locker,
        address _daoFeeRecipient,
        address _liquidityFeeRecipient,
        address _governance
    ) Accumulator(_gauge, _locker, _daoFeeRecipient, _liquidityFeeRecipient, _governance) {
        ERC20(CAKE).approve(_gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claim CAKE rewards for the locker and notify all to the LGV4
    function claimRevenueAndNotifyAll(address[] memory _revenueSharingPools) external {
        // claim CAKE reward
        ICakeLocker(locker).claimRevenue(_revenueSharingPools);
        uint256 cakeAmount = ERC20(CAKE).balanceOf(address(this));

        // notify CAKE in sdCAKE gauge
        _notifyReward(CAKE, cakeAmount);

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
