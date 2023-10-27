// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Strategy} from "src/base/strategy/Strategy.sol";
import {IYearnGauge} from "src/base/interfaces/IYearnGauge.sol";
import {IYearnRewardPool} from "src/base/interfaces/IYearnRewardPool.sol";
import {ISDTDistributor} from "src/base/interfaces/ISDTDistributor.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/// @title Yearn Strategy
/// @author StakeDAO
/// @notice Deposit/Withdraw in yearn gauges
contract YearnStrategy is Strategy {
    address public constant DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
    mapping(address => address) public rewardReceivers; // sdGauge -> rewardReceiver

    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    function setRewardReceiver(address _gauge, address _rewardReceiver) external onlyGovernanceOrAllowed {
        rewardReceivers[_gauge] = _rewardReceiver;
    }

    function claimDYfiRewardPool() external {
        // claim dYFI reward, locker receive it
        IYearnRewardPool(DYFI_REWARD_POOL).claim(address(locker));
        // transfer the whole dYFI locker's amount to the acc
        _transferFromLocker(rewardToken, accumulator, ERC20(rewardToken).balanceOf(address(locker)));
    }

    function _claimRewardToken(address _gauge) internal override returns (uint256 _claimed) {
        // claim the reward from the yearn gauge
        IYearnGauge(_gauge).getReward(address(locker));
        // transfer the whole balance here from the reward recipient
        address rewardReceiver = rewardReceivers[_gauge];
        _claimed = ERC20(rewardToken).balanceOf(rewardReceiver);
        ERC20(rewardToken).transferFrom(rewardReceiver, address(this), _claimed);
    }

    function _claimExtraRewards(address _gauge, address _rewardDistributor)
        internal
        override
        returns (uint256 _claimed)
    {}

    /// @notice Internal implementation of native reward claim compatible with FeeDistributor.vy like contracts.
    function _claimNativeRewards() internal override {
        locker.claimRewards(rewardToken, accumulator);
    }

    function _withdrawFromLocker(address _asset, address _gauge, uint256 _amount) internal override {
        /// Withdraw from the Gauge trough the Locker.
        locker.execute(
            _gauge,
            0,
            abi.encodeWithSignature("withdraw(uint256,address,address)", _amount, address(this), address(locker))
        );
    }
}
