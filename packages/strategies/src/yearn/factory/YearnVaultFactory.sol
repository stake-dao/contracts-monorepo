// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Vault} from "src/base/vault/Vault.sol";
import {PoolFactory} from "src/base/factory/PoolFactory.sol";
import {IYearnGauge} from "src/base/interfaces/IYearnGauge.sol";
import {IYearnRegistry} from "src/base/interfaces/IYearnRegistry.sol";
import {IGaugeController} from "src/base/interfaces/IGaugeController.sol";
import {RewardReceiverSingleToken} from "src/base/RewardReceiverSingleToken.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";

/// @title Factory contract used to create new yearn LP vaults.
contract YearnVaultFactory is PoolFactory {
    /// @notice Yearn Gauge Registry
    address public constant REGISTRY = 0x1D0fdCb628b2f8c0e22354d45B3B2D4cE9936F8B;

    /// @notice Emitted when a reward received is deployed
    event RewardReceiverDeployed(address _deployed, address _sdGauge);

    /// @notice Emitted when a governance change
    event GovernanceChanged(address _governance);

    /// @notice Throwed if the call failed
    error CALL_FAILED();

    /// @notice Throwed if caller is not allowed
    error NOT_ALLOWED();

    /// @notice Constructor.
    /// @param _strategy Address of the strategy contract. This contract should have the ability to add new reward tokens.
    /// @param _vaultImpl Address of the staking deposit implementation. Main entry point.
    /// @param _gaugeImpl Address of the liquidity gauge implementation.
    constructor(address _strategy, address _vaultImpl, address _gaugeImpl)
        PoolFactory(_strategy, address(0x41252E8691e964f7DE35156B68493bAb6797a275), _vaultImpl, _gaugeImpl)
    {}

    /// @notice Add new staking gauge to Stake DAO Locker.
    /// @param _gauge Address of the liquidity gauge.
    /// @return _vault Address of the staking deposit.
    /// @return _rewardDistributor Address of the reward distributor to claim rewards.
    function create(address _gauge) public override returns (address _vault, address _rewardDistributor) {
        /// Deploy Vault + Gauge.
        (_vault, _rewardDistributor) = super.create(_gauge);

        /// Deploy RewardReceiver.
        RewardReceiverSingleToken rewardReceiver = new RewardReceiverSingleToken(rewardToken, address(strategy));

        /// Set reward receiver in strategy.
        strategy.setRewardReceiver(_gauge, address(rewardReceiver));

        emit RewardReceiverDeployed(address(rewardReceiver), _rewardDistributor);
    }

    /// @notice Add extra reward tokens to the reward distributor.
    function _addExtraRewards(address) internal override {}

    /// @notice Retrieve the staking token from the gauge.
    /// @param _gauge Address of the liquidity gauge.
    function _getGaugeStakingToken(address _gauge) internal view override returns (address lp) {
        lp = ILiquidityGaugeStrat(_gauge).asset();
    }

    /// @notice Perform checks on the gauge to make sure it's valid and can be used.
    function _isValidGauge(address _gauge) internal view override returns (bool) {
        return IYearnRegistry(REGISTRY).registered(_gauge);
    }
}
