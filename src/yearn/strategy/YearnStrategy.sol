// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IYearnGauge} from "src/base/interfaces/IYearnGauge.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";
import {IYearnRewardPool} from "src/base/interfaces/IYearnRewardPool.sol";
import {ILocker, SafeExecute, Strategy} from "src/base/strategy/Strategy.sol";

/// @title Yearn Strategy
/// @author StakeDAO
/// @notice Deposit/Withdraw in Yearn Gauges.
contract YearnStrategy is Strategy {
    using SafeExecute for ILocker;

    /// @notice Reward Pool Contract to distribute DYFI.
    address public constant DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;

    /// @notice Mapping of Reward Distributors to Reward Receivers.
    mapping(address => address) public rewardReceivers;

    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    function claimDYfiRewardPool() external {
        /// Claim dYFI reward, locker receive it.
        IYearnRewardPool(DYFI_REWARD_POOL).claim(address(locker));
        /// Transfer the whole dYFI locker's amount to the acc.
        _transferFromLocker(rewardToken, accumulator, ERC20(rewardToken).balanceOf(address(locker)));
    }

    function _claimRewardToken(address _gauge) internal override returns (uint256 _claimed) {
        /// Claim the reward from the yearn gauge.
        IYearnGauge(_gauge).getReward(address(locker));

        /// Transfer the whole balance here from the reward recipient.
        address rewardReceiver = rewardReceivers[_gauge];
        _claimed = ERC20(rewardToken).balanceOf(rewardReceiver);

        SafeTransferLib.safeTransferFrom(rewardToken, rewardReceiver, address(this), _claimed);
    }

    function _claimExtraRewards(address _gauge, address _rewardDistributor)
        internal
        override
        returns (uint256 _claimed)
    {}

    /// @notice Internal implementation of native reward claim compatible with FeeDistributor.vy like contracts.
    function _claimNativeRewards() internal override {
        locker.claimRewards(feeRewardToken, accumulator);
    }

    function _withdrawFromLocker(address, address _gauge, uint256 _amount) internal override {
        /// Withdraw from the Gauge trough the Locker.
        locker.safeExecute(
            _gauge,
            0,
            abi.encodeWithSignature("withdraw(uint256,address,address)", _amount, address(this), address(locker))
        );
    }

    function setRewardReceiver(address _gauge, address _rewardReceiver) external onlyGovernanceOrFactory {
        rewardReceivers[_gauge] = _rewardReceiver;
    }
}