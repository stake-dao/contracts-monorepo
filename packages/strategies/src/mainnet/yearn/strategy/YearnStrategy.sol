// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IYearnGauge} from "src/common/interfaces/IYearnGauge.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {ISDTDistributor} from "src/common/interfaces/ISDTDistributor.sol";
import {IYearnRewardPool} from "src/common/interfaces/IYearnRewardPool.sol";
import {ILocker, SafeExecute, Strategy} from "src/common/strategy/Strategy.sol";

/// @notice Main access point of Yearn Locker.
contract YearnStrategy is Strategy {
    using SafeExecute for ILocker;

    /// @notice Reward Pool Contract to distribute DYFI.
    /// @dev Need to set it at deployment since it's a proxy.
    address public dyfiRewardPool = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;

    /// @notice Mapping of Reward Distributors to Reward Receivers.
    mapping(address => address) public rewardReceivers;

    /// @notice Constructor.
    /// @param _owner Address of the strategy owner.
    /// @param _locker Address of the locker.
    /// @param _veToken Address of the veToken.
    /// @param _rewardToken Address of the reward token.
    /// @param _minter Address of the platform minter.
    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    function claimDYFIRewardPool() external {
        /// Claim dYFI reward from the dYFI reward pool.
        IYearnRewardPool(dyfiRewardPool).claim(address(locker));

        /// Transfer the whole dYFI locker's amount to the acc.
        _transferFromLocker(rewardToken, accumulator, ERC20(rewardToken).balanceOf(address(locker)));
    }

    /// @notice Claim `rewardToken` allocated for a gauge.
    /// @param _gauge Address of the liquidity gauge to claim for.
    /// @return _claimed Number of DYFI claimed
    function _claimRewardToken(address _gauge) internal override returns (uint256 _claimed) {
        /// Claim the reward from the yearn gauge.
        IYearnGauge(_gauge).getReward(address(locker));

        /// Transfer the whole balance here from the reward recipient.
        address rewardReceiver = rewardReceivers[_gauge];
        _claimed = ERC20(rewardToken).balanceOf(rewardReceiver);

        SafeTransferLib.safeTransferFrom(rewardToken, rewardReceiver, address(this), _claimed);
    }

    /// @notice Claim extra rewards from the locker.
    function _claimExtraRewards(address, address) internal override returns (uint256) {}

    /// @notice Internal implementation of native reward claim compatible with FeeDistributor.vy like contracts.
    function _claimNativeRewards() internal override {
        /// Claim YFI from the YFI reward pool.
        locker.claimRewards(feeRewardToken, accumulator);
    }

    /// @notice Withdraw from the gauge through the Locker.
    /// @param _gauge Address of Liqudity gauge corresponding to LP token.
    /// @param _amount Amount of LP token to withdraw.
    function _withdrawFromLocker(address, address _gauge, uint256 _amount) internal override {
        /// Withdraw from the Gauge trough the Locker.
        locker.safeExecute(
            _gauge,
            0,
            abi.encodeWithSignature("withdraw(uint256,address,address)", _amount, address(this), address(locker))
        );
    }

    /// @notice Update the reward receiver for a gauge.
    /// @dev Make sure to claim all rewards from the previous receiver before updating.
    function setRewardReceiver(address _gauge, address _rewardReceiver) external onlyGovernanceOrFactory {
        /// Update the reward receiver.
        rewardReceivers[_gauge] = _rewardReceiver;

        /// Set the reward receiver in the gauge.
        locker.safeExecute(_gauge, 0, abi.encodeWithSignature("setRecipient(address)", address(_rewardReceiver)));
    }

    /// @notice Set the dYFI reward pool.
    function setDYFIRewardPool(address _dyfiRewardPool) external onlyGovernance {
        dyfiRewardPool = _dyfiRewardPool;
    }
}
