// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IPendleStrategy} from "@interfaces/stake-dao/IPendleStrategy.sol";
import {Factory} from "src/Factory.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IPendleGaugeController} from "src/interfaces/IPendleGaugeController.sol";
import {IPendleMarket} from "src/interfaces/IPendleMarket.sol";

/// @title PendleFactory.
/// @author Stake DAO
/// @custom:github @stake-dao
/// @custom:contact contact@stakedao.org
contract PendleFactory is Factory {
    /// @notice Bytes-4 protocol identifier for Pendle
    bytes4 private constant PENDLE_PROTOCOL_ID = bytes4(keccak256("PENDLE"));

    /// @notice Pendle Gauge Controller
    address public immutable GAUGE_CONTROLLER;

    /// @notice Address of the old strategy.
    address public immutable OLD_STRATEGY;

    constructor(
        address gaugeController,
        address oldStrategy,
        address protocolController,
        address vaultImplementation,
        address rewardReceiverImplementation,
        address locker,
        address gateway
    )
        Factory(protocolController, vaultImplementation, rewardReceiverImplementation, PENDLE_PROTOCOL_ID, locker, gateway)
    {
        GAUGE_CONTROLLER = gaugeController;
        OLD_STRATEGY = oldStrategy;
    }

    /// @notice Check if the gauge is valid
    function _isValidGauge(address _gauge) internal view virtual override returns (bool) {
        return IPendleGaugeController(GAUGE_CONTROLLER).isValidMarket(_gauge) && !IPendleMarket(_gauge).isExpired();
    }

    /// @notice Check that the gauge is no longer attached to the old strategy
    function _isValidDeployment(address _gauge) internal view virtual override returns (bool) {
        if (OLD_STRATEGY == address(0)) return true;

        // Check if the market (== LP token == gauge) is still managed by the old strategy
        try IPendleStrategy(OLD_STRATEGY).sdGauges(_gauge) returns (address oldSdGauge) {
            return oldSdGauge == address(0);
        } catch {
            return true;
        }
    }

    /// @dev In Pendle the LP token is the gauge share token.
    function _getAsset(address _gauge) internal view virtual override returns (address) {
        return _gauge;
    }

    function _setupRewardTokens(address _vault, address _gauge, address _rewardReceiver) internal virtual override {
        address[] memory rewardTokens = IPendleMarket(_gauge).getRewardTokens();
        uint256 length = rewardTokens.length;

        for (uint256 i; i < length; i++) {
            address rewardToken = rewardTokens[i];
            if (!_isValidToken(rewardToken)) continue;

            // If the reward token is already in the vault, skip.
            if (IRewardVault(_vault).isRewardToken(rewardToken)) continue;

            IRewardVault(_vault).addRewardToken(rewardToken, _rewardReceiver);
        }
    }

    function _setRewardReceiver(address _gauge, address _rewardReceiver) internal override {
        // No-op: Pendle markets have no explicit reward-receiver setter.
    }

    /// @dev No need to approve the assets for the gauge.
    function _initializeVault(address, address, address) internal override {
        // No-op: gauge tokens never leave the Locker.  Simply holding them is
        // sufficient for rewards to accrue.
    }
}
