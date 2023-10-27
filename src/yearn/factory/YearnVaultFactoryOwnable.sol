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
contract YearnVaultFactoryOwnable is PoolFactory {
    address public constant GAUGE_CONTROLLER = 0x41252E8691e964f7DE35156B68493bAb6797a275; // to change
    address public governance;
    address public futureGovernance;

    event RewardReceiverDeployed(address _deployed, address _sdGauge);
    event GovernanceChanged(address _governance);

    error CALL_FAILED();
    error NOT_ALLOWED();

    constructor(address _strategy, address _vaultImpl, address _gaugeImpl)
        PoolFactory(_strategy, address(0x41252E8691e964f7DE35156B68493bAb6797a275), _vaultImpl, _gaugeImpl)
    {
        governance = msg.sender;
    }

    function create(address _gauge) public override returns (address _vault, address _rewardDistributor) {
        if (msg.sender != governance) revert NOT_ALLOWED();
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

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external {
        if (msg.sender != governance) revert NOT_ALLOWED();
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert NOT_ALLOWED();

        governance = msg.sender;
        emit GovernanceChanged(msg.sender);
    }

    function _getGaugeStakingToken(address _gauge) internal view override returns (address lp) {
        lp = ILiquidityGaugeStrat(_gauge).asset();
    }

    function _isValidGauge(address _gauge) internal view override returns (bool) {
        return true;
    }

    function _addExtraRewards(address _gauge) internal override {}
}
