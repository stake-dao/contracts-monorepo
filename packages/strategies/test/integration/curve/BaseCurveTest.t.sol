// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/BaseFork.t.sol";

import {CurveFactory} from "src/integrations/curve/CurveFactory.sol";
import {CurveStrategy} from "src/integrations/curve/CurveStrategy.sol";
import {CurveAllocator} from "src/integrations/curve/CurveAllocator.sol";

import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {ConvexSidecarFactory} from "src/integrations/curve/ConvexSidecarFactory.sol";

import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";

abstract contract BaseCurveTest is BaseForkTest {
    /// @notice The protocol ID.
    bytes4 constant PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice The reward token.
    address constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice The locker.
    address constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    /// @notice The Boost Delegation V3 contract.
    address public constant BOOST_DELEGATION_V3 = 0xD37A6aa3d8460Bd2b6536d608103D880695A23CD;

    /// @notice The Convex Boost Holder contract.
    address public constant CONVEX_BOOST_HOLDER = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    /// @notice The old strategy.
    address public constant OLD_STRATEGY = 0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd;

    /// @notice The Curve Strategy contract.
    CurveStrategy public curveStrategy;

    /// @notice The Curve Factory contract.
    CurveFactory public curveFactory;

    /// @notice The Convex Sidecar contract.
    ConvexSidecar public convexSidecar;

    /// @notice The Convex Sidecar contract.
    ConvexSidecar public convexSidecarImplementation;

    /// @notice The Convex Sidecar Factory contract.
    ConvexSidecarFactory public convexSidecarFactory;

    constructor(address _lpToken, address _gauge) BaseForkTest(CRV, _lpToken, LOCKER, PROTOCOL_ID, false) {}

    function setUp() public override {
        vm.createSelectFork("mainnet");
        super.setUp();

        /// 1. Deploy the Curve Strategy contract.
        curveStrategy = new CurveStrategy(address(protocolController), LOCKER, address(gateway));

        /// 2. Deploy the Convex Sidecar contract.
        convexSidecarImplementation = new ConvexSidecar(address(accountant), address(protocolController));

        /// 3. Deploy the Convex Sidecar Factory contract.
        convexSidecarFactory =
            new ConvexSidecarFactory(address(convexSidecarImplementation), address(protocolController));

        /// 2. Deploy the Curve Factory contract.
        curveFactory = new CurveFactory({
            protocolController: address(protocolController),
            vaultImplementation: address(rewardVaultImplementation),
            rewardReceiverImplementation: address(rewardReceiverImplementation),
            locker: LOCKER,
            gateway: address(gateway),
            convexSidecarFactory: address(convexSidecarFactory)
        });

        /// 3. Setup the strategy in the protocol controller.
        protocolController.setStrategy(PROTOCOL_ID, address(curveStrategy));

        /// 4. Setup the factory in the protocol controller.
        protocolController.setRegistrar(address(curveFactory), true);

        /// 5. Enable Strategy and Factory as Module in Gateway.
        bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

        /// 6. Enable Strategy as Module in Gateway.
        gateway.execTransaction(
            address(gateway),
            0,
            abi.encodeWithSelector(IModuleManager.enableModule.selector, address(curveStrategy)),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signatures
        );

        /// 7. Enable Factory as Module in Gateway
        gateway.execTransaction(
            address(gateway),
            0,
            abi.encodeWithSelector(IModuleManager.enableModule.selector, address(curveFactory)),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signatures
        );
    }

    function test_deploy() public {
        address gauge = 0xd303994a0Db9b74f3E8fF629ba3097fC7060C331;
        uint256 pid = 421;

        /// 1. Deploy the Convex Sidecar.
        vm.expectRevert(ConvexSidecarFactory.VaultNotDeployed.selector);
        convexSidecar = ConvexSidecar(convexSidecarFactory.create(gauge, pid));
    }
}
