// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "forge-std/src/Script.sol";
import {Base} from "script/Base.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {ConvexSidecarFactory} from "src/integrations/curve/ConvexSidecarFactory.sol";
import {CurveAllocator} from "src/integrations/curve/CurveAllocator.sol";
import {CurveFactory} from "src/integrations/curve/CurveFactory.sol";
import {CurveStrategy} from "src/integrations/curve/CurveStrategy.sol";

contract Deploy is Base {
    string public NETWORK = "mainnet";
    address public DEPLOYER = 0xf1C9775ef36e1F633c362e3011589AC9781AB0ff;

    /// @notice The protocol ID.
    bytes4 internal constant PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice The reward token.
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice The locker address.
    /// @dev For the real deployment, replace with the actual locker address.
    address public LOCKER = 0x0000000000000000000000000000000000000000;

    /// @notice The minter contract.
    address internal constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    /// @notice Whether the strategy is harvested.
    bool public HARVESTED = false;

    /// @notice The Curve Strategy contract.
    CurveStrategy public curveStrategy;

    /// @notice The Curve Allocator contract.
    CurveAllocator public curveAllocator;

    /// @notice The Curve Factory contract.
    CurveFactory public curveFactory;

    /// @notice The Convex Sidecar contract.
    ConvexSidecar public convexSidecar;

    /// @notice The Convex Sidecar contract.
    ConvexSidecar public convexSidecarImplementation;

    /// @notice The Convex Sidecar Factory contract.
    ConvexSidecarFactory public convexSidecarFactory;

    function run() public {
        vm.createSelectFork(NETWORK);
        vm.startBroadcast(DEPLOYER);

        _run(DEPLOYER, CRV, LOCKER, PROTOCOL_ID, HARVESTED);

        /// 1. Deploy the Curve Strategy contract.
        curveStrategy = new CurveStrategy(address(protocolController), locker, address(gateway), MINTER);

        /// 2. Deploy the Convex Sidecar contract.
        convexSidecarImplementation = new ConvexSidecar(address(accountant), address(protocolController));

        /// 3. Deploy the Convex Sidecar Factory contract.
        convexSidecarFactory =
            new ConvexSidecarFactory(address(convexSidecarImplementation), address(protocolController));

        /// 4. Deploy the factory.
        curveFactory = new CurveFactory(
            address(protocolController),
            address(rewardVaultImplementation),
            address(rewardReceiverImplementation),
            locker,
            address(gateway),
            address(convexSidecarFactory)
        );

        /// 7. Deploy Allocator.
        curveAllocator = new CurveAllocator(address(protocolController), locker, address(convexSidecarFactory));

        /// 6. Setup the allocator in the protocol controller.
        protocolController.setAllocator(PROTOCOL_ID, address(curveAllocator));

        /// 7. Setup the strategy in the protocol controller.
        protocolController.setStrategy(PROTOCOL_ID, address(curveStrategy));

        /// 8. Setup the factory in the protocol controller.
        protocolController.setRegistrar(address(curveFactory), true);

        /// 9. Setup the convex sidecar factory in the protocol controller.
        protocolController.setRegistrar(address(convexSidecarFactory), true);

        /// 10. Enable Strategy as Module in Gateway.
        _enableModule(address(curveStrategy));

        /// 11. Enable Factory as Module in Gateway.
        _enableModule(address(curveFactory));

        /// 12. Allow minting of the reward token.
        bytes memory data = abi.encodeWithSignature("toggle_approve_mint(address)", address(curveStrategy));
        _executeTransaction(address(MINTER), data);

        vm.stopBroadcast();
    }
}
