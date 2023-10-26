// SPDX-License-Identifier: MIT
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
    address public constant GAUGE_CONTROLLER = 0x41252E8691e964f7DE35156B68493bAb6797a275; // to change

    event RewardReceiverDeployed(address _deployed, address _sdGauge);

    error CALL_FAILED();

    constructor(address _strategy, address _vaultImpl, address _gaugeImpl) PoolFactory(_strategy, address(0x41252E8691e964f7DE35156B68493bAb6797a275), _vaultImpl, _gaugeImpl) {
    }

    function create(address _gauge) public override returns (address _vault, address _rewardDistributor){
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

    function _getGaugeStakingToken(address _gauge) internal override view returns(address lp) {
        lp = ILiquidityGaugeStrat(_gauge).asset();
    }

    function _isValidGauge(address _gauge) internal override view returns(bool) {
        return true;
    }

    function _addExtraRewards(address _gauge) internal override {}

    // function _isValidGauge(address _gauge) internal override returns (bool valid) {
    //     // check if the gauge has been added into the yearn gc
    //     uint256 weight = IGaugeController(GAUGE_CONTROLLER).get_gauge_weight(_gauge);
    //     if (weight > 0) valid = true;
    // }
}
