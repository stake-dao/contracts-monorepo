// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/factory/PoolFactoryXChain.sol";
import {Vault} from "src/common/vault/Vault.sol";
import {ICakeV2Wrapper} from "src/common/interfaces/ICakeV2Wrapper.sol";
import {ICakeFarmBooster} from "src/common/interfaces/ICakeFarmBooster.sol";

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

    /// @notice Deploy a new vault.
    /// @param lp Address of the LP token.
    /// @param gauge Address of the liquidity gauge.
    /// @param rewardDistributor Address of the reward distributor.
    /// @return vault Address of the new vault.
    function _deployVault(address lp, address gauge, address rewardDistributor)
        internal
        override
        returns (address vault)
    {
        /// We use the LP token and the gauge address as salt to generate the vault address.
        bytes32 salt = keccak256(abi.encodePacked(lp, gauge));

        /// We use CWIA setup. We encode the LP token, the strategy address and the reward distributor address as data
        /// to be passed as immutable args to the vault.
        bytes memory vaultData = abi.encodePacked(lp, address(strategy), rewardDistributor, adapterRegistry);

        vault = vaultImplementation.cloneDeterministic(vaultData, salt);
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
