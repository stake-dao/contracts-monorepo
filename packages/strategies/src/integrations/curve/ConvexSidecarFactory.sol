// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {SidecarFactory} from "src/SidecarFactory.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {IBooster, IL2Booster} from "@interfaces/convex/IBooster.sol";

/// @title ConvexSidecarFactory
/// @notice Factory contract for deploying ConvexSidecar instances
/// @dev Creates deterministic minimal proxies for ConvexSidecar implementation
contract ConvexSidecarFactory is SidecarFactory {
    /// @notice Chain ID.
    uint256 public immutable CHAIN_ID;

    /// @notice The bytes4 ID of the Convex protocol
    /// @dev Used to identify the Convex protocol in the registry
    bytes4 private constant CURVE_PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice Convex Booster contract address
    address public immutable BOOSTER;

    /// @notice Error emitted when the pool is shutdown
    error PoolShutdown();

    /// @notice Error emitted when the reward receiver is not set
    error VaultNotDeployed();

    /// @notice Error emitted when the arguments are invalid
    error InvalidArguments();

    /// @notice Constructor
    /// @param _implementation Address of the sidecar implementation
    /// @param _protocolController Address of the protocol controller
    /// @param _booster Address of the Convex Booster contract
    constructor(address _implementation, address _protocolController, address _booster)
        SidecarFactory(CURVE_PROTOCOL_ID, _implementation, _protocolController)
    {
        BOOSTER = _booster;
        CHAIN_ID = block.chainid;
    }

    /// @notice Convenience function to create a sidecar with a uint256 pid parameter
    /// @param pid Pool ID in Convex
    /// @return sidecar Address of the created sidecar
    function create(address gauge, uint256 pid) external returns (address sidecar) {
        bytes memory args = abi.encode(pid);
        return create(gauge, args);
    }

    /// @notice Validates the gauge and arguments for Convex
    /// @param gauge The gauge to validate
    /// @param args The arguments containing the pool ID
    function _isValidGauge(address gauge, bytes memory args) internal view override {
        require(args.length == 32, InvalidArguments());

        uint256 pid = abi.decode(args, (uint256));

        address curveGauge;
        bool isShutdown;

        if (CHAIN_ID == 1) {
            // Get the pool info from Convex
            (,, curveGauge,,, isShutdown) = IBooster(BOOSTER).poolInfo(pid);
        } else {
            // Get the pool info from Convex
            (, curveGauge,, isShutdown,) = IL2Booster(BOOSTER).poolInfo(pid);
        }

        // Ensure the pool is not shutdown
        if (isShutdown) revert PoolShutdown();

        // Ensure the gauge matches
        if (curveGauge != gauge) revert InvalidGauge();
    }

    /// @notice Creates a ConvexSidecar for a gauge
    /// @param gauge The gauge to create a sidecar for
    /// @param args The arguments containing the pool ID
    /// @return sidecarAddress Address of the created sidecar
    function _create(address gauge, bytes memory args) internal override returns (address sidecarAddress) {
        uint256 pid = abi.decode(args, (uint256));

        // Get the LP token and base reward pool from Convex
        address lpToken;
        address baseRewardPool;

        if (CHAIN_ID == 1) {
            (lpToken,,, baseRewardPool,,) = IBooster(BOOSTER).poolInfo(pid);
        } else {
            (lpToken,, baseRewardPool,,) = IL2Booster(BOOSTER).poolInfo(pid);
        }

        address rewardReceiver = PROTOCOL_CONTROLLER.rewardReceiver(gauge);
        require(rewardReceiver != address(0), VaultNotDeployed());

        // Encode the immutable arguments for the clone
        bytes memory data = abi.encodePacked(lpToken, rewardReceiver, baseRewardPool, pid);

        // Create a deterministic salt based on the token and gauge
        bytes32 salt = keccak256(data);

        // Clone the implementation contract
        sidecarAddress = Clones.cloneDeterministicWithImmutableArgs(IMPLEMENTATION, data, salt);

        // Initialize the sidecar
        ConvexSidecar(sidecarAddress).initialize();

        // Set the valid allocation target
        PROTOCOL_CONTROLLER.setValidAllocationTarget(gauge, sidecarAddress);

        return sidecarAddress;
    }
}
