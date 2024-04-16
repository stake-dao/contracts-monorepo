// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Vault} from "src/base/vault/Vault.sol";
import {PoolFactoryXChain} from "src/base/factory/PoolFactoryXChain.sol";
import {ICakeV2Wrapper} from "src/base/interfaces/ICakeV2Wrapper.sol";

/// @title Factory contract used to create new yearn LP vaults.
contract PancakeVaultFactoryXChain is PoolFactoryXChain {
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
    constructor(address _strategy, address _vaultImpl, address _gaugeImpl, address _rewardToken)
        PoolFactoryXChain(_strategy, _rewardToken, _vaultImpl, _gaugeImpl)
    {}

    /// @notice Retrieve the staking token from the gauge.
    /// @param _gauge Address of the liquidity gauge.
    function _getGaugeStakingToken(address _gauge) internal view override returns (address lp) {
        lp = ICakeV2Wrapper(_gauge).stakedToken();
    }

    /// @notice Perform checks on the gauge to make sure it's valid and can be used.
    function _isValidGauge(address) internal pure override returns (bool) {
        return true;
    }
}
