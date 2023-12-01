// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Accumulator} from "src/base/accumulator/Accumulator.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ICakeLocker} from "src/base/interfaces/ICakeLocker.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IRevenueSharingPool} from "src/base/interfaces/IRevenueSharingPool.sol";
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
    /// @param _revenueSharingPools pancake revenue sharing pools
    /// @param _notifySDT if notify SDT or not
    /// @param _pullFromFeeSplitter if pull tokens from the fee splitter or not
    function claimAndNotifyAll(address[] memory _revenueSharingPools, bool _notifySDT, bool _pullFromFeeSplitter)
        external
    {
        // claim Revenue reward
        ICakeLocker(locker).claimRevenue(_revenueSharingPools);

        for (uint256 i; i < _revenueSharingPools.length;) {
            address tokenReward = IRevenueSharingPool(_revenueSharingPools[i]).rewardToken();
            uint256 balance = ERC20(tokenReward).balanceOf(address(this));
            // notify reward only one time for each different token
            if (balance != 0) {
                notifyReward(tokenReward, _notifySDT, _pullFromFeeSplitter);
            }
            unchecked {
                i++;
            }
        }
    }

    /// @notice Notify the new reward to the LGV4
    /// @param _tokenReward token to notify
    /// @param _amount amount to notify
    function _notifyReward(address _tokenReward, uint256 _amount) internal override {
        // check if the reward token needs to 
        _approveTokenIfNeeded(_tokenReward, _amount);
        super._notifyReward(_tokenReward, _amount);
    }

    /// @notice Approve the reward token to be transferred by the gauge if needed
    /// @param _token token to approve
    /// @param _amount amount to check the allowance
    function _approveTokenIfNeeded(address _token, uint256 _amount) internal {
        if (ERC20(_token).allowance(address(this), gauge) < _amount) {
            // do an max approve
            ERC20(_token).approve(gauge, type(uint256).max);
        }
    }
}
