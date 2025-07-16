// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Factory} from "src/Factory.sol";
import {IL2Booster} from "@interfaces/convex/IL2Booster.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {ISidecarFactory} from "src/interfaces/ISidecarFactory.sol";
import {IL2LiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IChildLiquidityGaugeFactory} from "@interfaces/curve/IChildLiquidityGaugeFactory.sol";

contract CurveFactory is Factory, Ownable2Step {
    /// @notice The bytes4 ID of the Curve protocol
    /// @dev Used to identify the Curve protocol in the registry
    bytes4 private constant CURVE_PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice Convex Booster.
    address public immutable BOOSTER;

    /// @notice Convex Minimal Proxy Factory for Only Boost.
    address public immutable CONVEX_SIDECAR_FACTORY;

    /// @notice The child liquidity gauge factories.
    IChildLiquidityGaugeFactory[] public childLiquidityGaugeFactories;

    /// @notice Error thrown when the set reward receiver fails.
    error SetRewardReceiverFailed();

    /// @notice Error thrown when the convex sidecar factory is not set.
    error ConvexSidecarFactoryNotSet();

    /// @notice Error thrown when the child liquidity gauge factories are not set.
    error ChildLiquidityGaugeFactoriesNotSet();

    /// @notice Event emitted when a vault is deployed.
    event VaultDeployed(address gauge, address vault, address rewardReceiver, address sidecar);

    constructor(
        address admin,
        address protocolController,
        address vaultImplementation,
        address rewardReceiverImplementation,
        address locker,
        address gateway,
        address booster,
        address convexSidecarFactory
    )
        Factory(protocolController, vaultImplementation, rewardReceiverImplementation, CURVE_PROTOCOL_ID, locker, gateway)
        Ownable(admin)
    {
        BOOSTER = booster;
        CONVEX_SIDECAR_FACTORY = convexSidecarFactory;
    }

    /// @notice Create a new vault.
    /// @param _pid Pool id.
    function create(uint256 _pid) external returns (address vault, address rewardReceiver, address sidecar) {
        require(CONVEX_SIDECAR_FACTORY != address(0), ConvexSidecarFactoryNotSet());

        (, address gauge,,,) = IL2Booster(BOOSTER).poolInfo(_pid);

        /// 1. Create the vault.
        (vault, rewardReceiver) = createVault(gauge);

        /// 2. Attach the sidecar.
        sidecar = ISidecarFactory(CONVEX_SIDECAR_FACTORY).create(gauge, abi.encode(_pid));

        /// 3. Emit the event.
        emit VaultDeployed(gauge, vault, rewardReceiver, sidecar);
    }

    function _isValidToken(address _token) internal view virtual override returns (bool) {
        /// If the token is not valid, return false.
        if (!super._isValidToken(_token)) return false;
        require(childLiquidityGaugeFactories.length > 0, ChildLiquidityGaugeFactoriesNotSet());

        /// If the token is available as an inflation receiver, it's not valid.
        for (uint256 i = 0; i < childLiquidityGaugeFactories.length; i++) {
            if (childLiquidityGaugeFactories[i].is_valid_gauge(_token)) {
                return false;
            }
        }

        return true;
    }

    function _isValidGauge(address _gauge) internal view virtual override returns (bool isValid) {
        require(childLiquidityGaugeFactories.length > 0, ChildLiquidityGaugeFactoriesNotSet());
        /// Check if the gauge is a valid candidate and available as an inflation receiver.
        /// This call always reverts if the gauge is not valid.
        for (uint256 i = 0; i < childLiquidityGaugeFactories.length; i++) {
            if (childLiquidityGaugeFactories[i].is_valid_gauge(_gauge)) {
                isValid = true;
                break;
            }
        }

        /// Check if the gauge is not killed.
        if (IL2LiquidityGauge(_gauge).is_killed()) {
            isValid = false;
        }

        return isValid;
    }

    function _getAsset(address _gauge) internal view virtual override returns (address) {
        return IL2LiquidityGauge(_gauge).lp_token();
    }

    function _setupRewardTokens(address _vault, address _gauge, address _rewardReceiver) internal virtual override {
        /// Check if the gauge supports extra rewards.
        /// This function is not supported on all gauges, depending on when they were deployed.
        bytes memory data = abi.encodeWithSignature("reward_tokens(uint256)", 0);

        (bool success,) = _gauge.call(data);
        if (!success) return;

        /// Loop through the extra reward tokens.
        /// 8 is the maximum number of extra reward tokens supported by the gauges.
        for (uint8 i = 0; i < 8; i++) {
            /// Get the extra reward token address.
            address _extraRewardToken = IL2LiquidityGauge(_gauge).reward_tokens(i);
            (, uint256 periodFinish,,,) = IL2LiquidityGauge(_gauge).reward_data(_extraRewardToken);
            /// If the reward data is not active, skip.
            if (periodFinish < block.timestamp) continue;
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

    /// @notice Set the child liquidity gauge factories.
    /// @param _childLiquidityGaugeFactories The child liquidity gauge factories.
    function setChildLiquidityGaugeFactories(IChildLiquidityGaugeFactory[] memory _childLiquidityGaugeFactories)
        external
        onlyOwner
    {
        childLiquidityGaugeFactories = _childLiquidityGaugeFactories;
    }
}
