// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IBooster} from "@interfaces/convex/IBooster.sol";
import {SidecarFactory} from "src/SidecarFactory.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";

/// @title ConvexSidecarFactory
/// @notice Factory contract for deploying ConvexSidecar instances
/// @dev Creates deterministic minimal proxies for ConvexSidecar implementation
contract ConvexSidecarFactory is SidecarFactory {
    /// @notice CVX token address
    address public immutable CVX;

    /// @notice Convex Booster contract address
    address public immutable BOOSTER;

    /// @notice Error emitted when the pool is shutdown
    error PoolShutdown();

    /// @notice Constructor
    /// @param _cvx Address of the CVX token
    /// @param _booster Address of the Convex Booster contract
    /// @param _implementation Address of the sidecar implementation
    /// @param _protocolController Address of the protocol controller
    /// @param _protocolId Protocol ID
    constructor(
        address _cvx,
        address _booster,
        address _implementation,
        address _protocolController,
        bytes4 _protocolId
    ) SidecarFactory(_protocolId, _implementation, _protocolController) {
        if (_booster == address(0) || _cvx == address(0)) {
            revert ZeroAddress();
        }

        CVX = _cvx;
        BOOSTER = _booster;
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
        uint256 pid = abi.decode(args, (uint256));

        // Get the pool info from Convex
        (,, address curveGauge,,, bool isShutdown) = IBooster(BOOSTER).poolInfo(pid);

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
        (address lpToken,,, address baseRewardPool,,) = IBooster(BOOSTER).poolInfo(pid);

        // Encode the immutable arguments for the clone
        bytes memory data = abi.encodePacked(lpToken, REWARD_TOKEN, STRATEGY, CVX, BOOSTER, baseRewardPool, pid);

        // Create a deterministic salt based on the token and gauge
        bytes32 salt = keccak256(abi.encodePacked(lpToken, gauge));

        // Clone the implementation contract
        sidecarAddress = Clones.cloneDeterministicWithImmutableArgs(IMPLEMENTATION, data, salt);

        // Initialize the sidecar
        ConvexSidecar(sidecarAddress).initialize();

        return sidecarAddress;
    }
}
