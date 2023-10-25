// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VaultFactory} from "src/base/factory/VaultFactory.sol";
import {StrategyVaultImpl} from "src/base/vault/StrategyVaultImpl.sol";
import {RewardReceiverSingleToken} from "src/base/RewardReceiverSingleToken.sol";
import {IGaugeController} from "src/base/interfaces/IGaugeController.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";

/**
 * @title Factory contract used to create new yearn LP vaults
 */
contract YearnVaultFactory is VaultFactory {
    address public rewardToken = 0x41252E8691e964f7DE35156B68493bAb6797a275; // dYFI
    address public constant GAUGE_CONTROLLER = 0x41252E8691e964f7DE35156B68493bAb6797a275; // to change

    event RewardReceiverDeployed(address _deployed);

    constructor(address _strategy, address _sdtDistributor, address _vaultImpl, address _gaugeImpl) VaultFactory(_strategy, _sdtDistributor, _vaultImpl, _gaugeImpl) {}

    function cloneAndInit(address _gauge) public override {
        // deploy Vault + Gauge
        super.cloneAndInit(_gauge);
        // deploy RewardReceiver
        ILiquidityGaugeStrat sdGauge = ILiquidityGaugeStrat(strategy.rewardDistributors(_gauge));
         RewardReceiverSingleToken rewardReceiver =
            new RewardReceiverSingleToken(rewardToken, address(sdGauge),  address(strategy));
        sdGauge.add_reward(rewardToken, address(rewardReceiver));
        sdGauge.commit_transfer_ownership(GOVERNANCE);

    }

    function _getGaugeLp(address _gauge) internal override view returns(address lp) {
        lp = ILiquidityGaugeStrat(_gauge).asset();
    }

    // function _isValidGauge(address _gauge) internal override returns (bool valid) {
    //     // check if the gauge has been added into the yearn gc
    //     uint256 weight = IGaugeController(GAUGE_CONTROLLER).get_gauge_weight(_gauge);
    //     if (weight > 0) valid = true;
    // }
}
