// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IBooster} from "@interfaces/convex/IBooster.sol";
import {IGaugeController} from "@interfaces/curve/IGaugeController.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {IStrategy} from "@interfaces/stake-dao/IStrategy.sol";
import {Factory} from "src/Factory.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {ISidecarFactory} from "src/interfaces/ISidecarFactory.sol";

contract CurveFactory is Factory {
    /// @notice The bytes4 ID of the Curve protocol
    /// @dev Used to identify the Curve protocol in the registry
    bytes4 private constant CURVE_PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice Curve Gauge Controller.
    IGaugeController public constant GAUGE_CONTROLLER = IGaugeController(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);

    /// @notice CVX token address.
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    /// @notice Address of the old strategy.
    address public constant OLD_STRATEGY = 0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd;

    /// @notice Convex Booster.
    address public immutable BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /// @notice Convex Minimal Proxy Factory for Only Boost.
    address public immutable CONVEX_SIDECAR_FACTORY;

    /// @notice Error thrown when the set reward receiver fails.
    error SetRewardReceiverFailed();

    /// @notice Event emitted when a vault is deployed.
    event VaultDeployed(address gauge, address vault, address rewardReceiver, address sidecar);

    constructor(
        address protocolController,
        address vaultImplementation,
        address rewardReceiverImplementation,
        address locker,
        address gateway,
        address convexSidecarFactory
    )
        Factory(protocolController, vaultImplementation, rewardReceiverImplementation, CURVE_PROTOCOL_ID, locker, gateway)
    {
        CONVEX_SIDECAR_FACTORY = convexSidecarFactory;
    }

    /// @notice Create a new vault.
    /// @param _pid Pool id.
    function create(uint256 _pid) external returns (address vault, address rewardReceiver, address sidecar) {
        (,, address gauge,,,) = IBooster(BOOSTER).poolInfo(_pid);

        /// 1. Create the vault.
        (vault, rewardReceiver) = createVault(gauge);

        /// 2. Attach the sidecar.
        sidecar = ISidecarFactory(CONVEX_SIDECAR_FACTORY).create(gauge, abi.encode(_pid));

        /// 3. Set the valid allocation target.
        PROTOCOL_CONTROLLER.setValidAllocationTarget(gauge, sidecar);

        emit VaultDeployed(gauge, vault, rewardReceiver, sidecar);
    }

    function _isValidToken(address _token) internal view virtual override returns (bool) {
        /// If the token is not valid, return false.
        if (!super._isValidToken(_token)) return false;

        /// We already add CVX to the vault by default.
        if (_token == CVX) return false;

        /// If the token is available as an inflation receiver, it's not valid.
        try GAUGE_CONTROLLER.gauge_types(_token) {
            return false;
        } catch {
            return true;
        }
    }

    function _isValidGauge(address _gauge) internal view virtual override returns (bool) {
        bool isValid;
        /// Check if the gauge is a valid candidate and available as an inflation receiver.
        /// This call always reverts if the gauge is not valid.
        try GAUGE_CONTROLLER.gauge_types(_gauge) {
            isValid = true;
        } catch {
            return false;
        }

        /// Check if the gauge is not killed.
        /// Not all the pools, but most of them, have this function.
        try ILiquidityGauge(_gauge).is_killed() returns (bool isKilled) {
            if (isKilled) return false;
        } catch {}

        /// If the gauge doesn't support the is_killed function, but is unofficially killed, it can be deployed.
        return isValid;
    }

    /// @notice Check if the gauge is shutdown in the old strategy.
    /// @dev If the gauge is shutdown, we can deploy a new strategy.
    function _isValidDeployment(address _gauge) internal view virtual override returns (bool) {
        /// We check if the gauge is deployed in the old strategy by checking if the reward distributor is not 0.
        /// We also check if the gauge is shutdown.
        return IStrategy(OLD_STRATEGY).rewardDistributors(_gauge) != address(0)
            && IStrategy(OLD_STRATEGY).isShutdown(_gauge);
    }

    function _getAsset(address _gauge) internal view virtual override returns (address) {
        return ILiquidityGauge(_gauge).lp_token();
    }

    function _setupRewardTokens(address _vault, address _gauge, address _rewardReceiver) internal virtual override {
        /// Add CVX to the vault if it's not already there.
        if (!IRewardVault(_vault).isRewardToken(CVX)) {
            IRewardVault(_vault).addRewardToken(CVX, _rewardReceiver);
        }

        /// Check if the gauge supports extra rewards.
        /// This function is not supported on all gauges, depending on when they were deployed.
        bytes memory data = abi.encodeWithSignature("reward_tokens(uint256)", 0);

        (bool success,) = _gauge.call(data);
        if (!success) return;

        /// Loop through the extra reward tokens.
        /// 8 is the maximum number of extra reward tokens supported by the gauges.
        for (uint8 i = 0; i < 8; i++) {
            /// Get the extra reward token address.
            address _extraRewardToken = ILiquidityGauge(_gauge).reward_tokens(i);

            /// If the address is 0, it means there are no more extra reward tokens.
            if (_extraRewardToken == address(0)) break;
            /// If the extra reward token is already in the vault, skip.
            if (IRewardVault(_vault).isRewardToken(_extraRewardToken)) continue;
            /// Performs checks on the extra reward token.
            /// Checks like if the token is also an lp token that can be staked in the locker, these tokens are not supported.
            if (_isValidToken(_extraRewardToken)) {
                /// Then we add the extra reward token to the reward distributor through the strategy.
                IRewardVault(_vault).addRewardToken(_extraRewardToken, _rewardReceiver);
            }
        }
    }

    function _setRewardReceiver(address _gauge, address _rewardReceiver) internal override {
        /// Set RewardReceiver as RewardReceiver on Gauge.
        bytes memory data = abi.encodeWithSignature("set_rewards_receiver(address)", _rewardReceiver);
        require(_executeTransaction(_gauge, data), SetRewardReceiverFailed());
    }

    function _initializeVault(address, address _asset, address _gauge) internal override {
        /// Initialize the vault.
        /// We need to approve the asset to the gauge using the Locker.
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", _gauge, type(uint256).max);

        /// Execute the transaction.
        require(_executeTransaction(_asset, data), ApproveFailed());
    }
}
