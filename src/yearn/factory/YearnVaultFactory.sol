// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "src/base/factory/VaultFactory.sol";
import "src/base/vault/StrategyVault.sol";
import "src/base/RewardReceiverSingleToken.sol";
import "src/base/interfaces/IGaugeController.sol";

/**
 * @title Factory contract used to create new yearn LP vaults
 */
contract YearnVaultFactory is VaultFactory {
    address public rewardToken = 0x41252E8691e964f7DE35156B68493bAb6797a275; // dYFI
    address public constant GAUGE_CONTROLLER = 0x41252E8691e964f7DE35156B68493bAb6797a275; // to change

    event RewardReceiverDeployed(address _deployed);

    constructor(address _strategy, address _sdtDistributor) VaultFactory(_strategy, _sdtDistributor, address(0)) {
        StrategyVault vault = new StrategyVault();
        vaultImpl = address(vault);
    }

    function cloneAndInit(address _gauge) public override {
        // deploy Vault + Gauge
        super.cloneAndInit(_gauge);
        // deploy RewardReceiver
        // address sdGauge = strategy.rewardDistributor(_gauge);
        // RewardReceiverSingleToken rewardReceiver =
        //     new RewardReceiverSingleToken(rewardToken, sdGauge,  address(strategy));
        // ILiquidityGaugeStrat(sdGauge).add_reward(rewardToken, address(rewardReceiver));
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
