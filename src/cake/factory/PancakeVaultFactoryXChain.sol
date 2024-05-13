// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/factory/PoolFactoryXChain.sol";
import {Vault} from "src/base/vault/Vault.sol";
import {ICakeV2Wrapper} from "src/base/interfaces/ICakeV2Wrapper.sol";
import {ICakeFarmBooster} from "src/base/interfaces/ICakeFarmBooster.sol";

/// @title Factory contract used to create new pancake V2/StableSwap/PositionManager LP vaults.
contract PancakeVaultFactoryXChain is PoolFactoryXChain {
    using LibClone for address;

    /// @notice Address of the adapter registry.
    address public immutable adapterRegistry;

    /// @notice Address of the Farm Booster to check if the gauge is valid.
    address public constant FARM_BOOSTER = 0x5dbC7e443cCaD0bFB15a081F1A5C6BA0caB5b1E6;

    /// @notice Address of the claimer contract.
    address public constant CLAIMER = 0xA3d2849905B92cB052848d2778955E3749755dA1;

    /// @notice Constructor.
    /// @param _strategy Address of the strategy contract. This contract should have the ability to add new reward tokens.
    /// @param _vaultImpl Address of the staking deposit implementation. Main entry point.
    /// @param _gaugeImpl Address of the liquidity gauge implementation.
    constructor(
        address _strategy,
        address _vaultImpl,
        address _gaugeImpl,
        address _rewardToken,
        address _adapterRegistry
    ) PoolFactoryXChain(_strategy, _rewardToken, _vaultImpl, _gaugeImpl, CLAIMER) {
        adapterRegistry = _adapterRegistry;
    }

    /// @notice Add new staking gauge to Stake DAO Locker.
    /// @param _gauge Address of the liquidity gauge.
    /// @return vault Address of the staking deposit.
    /// @return rewardDistributor Address of the reward distributor to claim rewards.
    function create(address _gauge) public override returns (address vault, address rewardDistributor) {
        /// Perform checks on the gauge to make sure it's valid and can be used.
        if (!_isValidGauge(_gauge)) revert INVALID_GAUGE();

        /// Perform checks on the strategy to make sure it's not already used.
        if (strategy.rewardDistributors(_gauge) != address(0)) revert GAUGE_ALREADY_USED();

        /// Retrieve the staking token.
        address lp = _getGaugeStakingToken(_gauge);

        /// Clone the Reward Distributor.
        rewardDistributor = LibClone.clone(liquidityGaugeImplementation);

        /// We use the LP token and the gauge address as salt to generate the vault address.
        bytes32 salt = keccak256(abi.encodePacked(lp, _gauge));

        /// We use CWIA setup. We encode the LP token, the strategy address and the reward distributor address as data
        /// to be passed as immutable args to the vault.
        bytes memory vaultData = abi.encodePacked(lp, address(strategy), rewardDistributor, adapterRegistry);

        /// Clone the Vault.
        vault = vaultImplementation.cloneDeterministic(vaultData, salt);

        /// Retrieve the symbol to be used on the reward distributor.
        (, string memory _symbol) = _getNameAndSymbol(lp);

        /// Initialize the Reward Distributor.
        ILiquidityGaugeStrat(rewardDistributor).initialize(vault, address(this), vault, _symbol);

        /// Initialize Vault.
        IStrategyVault(vault).initialize();

        /// Allow the vault to stake the LP token in the locker trough the strategy.
        strategy.toggleVault(vault);

        /// Map in the strategy the staking token to it's corresponding gauge.
        strategy.setGauge(lp, _gauge);

        /// Map the gauge to the reward distributor that should receive the rewards.
        strategy.setRewardDistributor(_gauge, rewardDistributor);

        /// Add the reward token to the reward distributor.
        _addRewardToken(rewardDistributor);

        /// Set ClaimHelper as claimer.
        ILiquidityGaugeStrat(rewardDistributor).set_claimer(claimHelper);

        /// Transfer ownership of the reward distributor to the strategy.
        ILiquidityGaugeStrat(rewardDistributor).commit_transfer_ownership(address(strategy));

        /// Accept ownership of the reward distributor.
        strategy.acceptRewardDistributorOwnership(rewardDistributor);

        /// Add extra rewards if any.
        _addExtraRewards(_gauge);

        emit PoolDeployed(vault, rewardDistributor, lp, _gauge);
    }

    /// @notice Retrieve the staking token from the gauge.
    /// @param _gauge Address of the liquidity gauge.
    function _getGaugeStakingToken(address _gauge) internal view override returns (address lp) {
        lp = ICakeV2Wrapper(_gauge).stakedToken();
    }

    /// @notice Retrieve the name and symbol of the staking token.
    function _getNameAndSymbol(address) internal pure override returns (string memory name, string memory symbol) {
        name = "PCS-ERC20";
        symbol = "PCS-ERC20";
    }

    /// @notice Perform checks on the gauge to make sure it's valid and can be used.
    function _isValidGauge(address _gauge) internal view override returns (bool) {
        return ICakeFarmBooster(FARM_BOOSTER).whiteListWrapper(_gauge);
    }
}
