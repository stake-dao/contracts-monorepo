// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {PoolFactory} from "src/base/factory/PoolFactory.sol";
import {StrategyVaultImpl} from "src/base/vault/StrategyVaultImpl.sol";
import {RewardReceiverSingleToken} from "src/base/RewardReceiverSingleToken.sol";
import {IGaugeController} from "src/base/interfaces/IGaugeController.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {IYearnGauge} from "src/base/interfaces/IYearnGauge.sol";

/**
 * @title Factory contract used to create new yearn LP vaults
 */
contract YearnVaultFactory is PoolFactory {
    /// @notice Platform's gauge controller (TO_CHANGE_BEFORE_DEPLOY)
    address public constant GAUGE_CONTROLLER = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    /// @notice Emitted when a reward received is deployed
    event RewardReceiverDeployed(address _deployed, address _sdGauge);

    /// @notice Throwed if the call failed.
    error CALL_FAILED();

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
        // deploy Vault + Gauge
        (_vault, _rewardDistributor) = super.create(_gauge);
        // deploy RewardReceiver
        RewardReceiverSingleToken rewardReceiver = new RewardReceiverSingleToken(rewardToken, address(strategy));

        // set reward receiver in yearn gauge via locker
        bytes memory data = abi.encodeWithSignature("setRecipient(address)", address(rewardReceiver));
        bytes memory lockerData = abi.encodeWithSignature("execute(address,uint256,bytes)", _gauge, 0, data);
        (bool success,) = strategy.execute(strategy.locker(), 0, lockerData);
        if (!success) revert CALL_FAILED();

        // set reward receiver in strategy
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
    /// @param _gauge platform gauge address
    /// @return valid if the gauge is valid or not
    function _isValidGauge(address _gauge) internal view override returns (bool valid) {
        // check if the gauge has been added into the yearn gc
        uint256 weight = IGaugeController(GAUGE_CONTROLLER).get_gauge_weight(_gauge);
        if (weight > 0) valid = true;
    }
}
