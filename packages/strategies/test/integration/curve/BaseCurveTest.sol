// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/BaseFork.sol";

import {CurveStrategy, IMinter} from "src/integrations/curve/CurveStrategy.sol";
import {CurveAllocator} from "src/integrations/curve/CurveAllocator.sol";
import {CurveFactory, Factory, IProtocolController} from "src/integrations/curve/CurveFactory.sol";

import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {ConvexSidecarFactory, IBooster} from "src/integrations/curve/ConvexSidecarFactory.sol";

import {IStrategy} from "@interfaces/stake-dao/IStrategy.sol";
import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {IBalanceProvider} from "src/interfaces/IBalanceProvider.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";

abstract contract BaseCurveTest is BaseForkTest {
    ///////////////////////////////////////////////////////////////////////////
    //// - CONSTANTS
    ///////////////////////////////////////////////////////////////////////////

    /// @notice The protocol ID.
    bytes4 constant PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice The reward token.
    address constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice The minter contract.
    address constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    /// @notice The locker.
    address constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    /// @notice The Boost Delegation V3 contract.
    address public constant BOOST_DELEGATION_V3 = 0xD37A6aa3d8460Bd2b6536d608103D880695A23CD;

    /// @notice The Convex Boost Holder contract.
    address public constant CONVEX_BOOST_HOLDER = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    /// @notice The Booster contract.
    IBooster public constant BOOSTER = IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    /// @notice The old strategy.
    address public constant OLD_STRATEGY = 0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd;

    ///////////////////////////////////////////////////////////////////////////
    //// - HELPER STORAGE
    ///////////////////////////////////////////////////////////////////////////

    /// @notice The signature for the Safe transaction.
    bytes signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

    ///////////////////////////////////////////////////////////////////////////
    //// - TEST STORAGE
    ///////////////////////////////////////////////////////////////////////////

    /// @notice The PID.
    uint256 public pid;

    /// @notice  The Staking Token.
    address public lpToken;

    /// @notice The total supply of the LP token.
    uint256 public totalSupply;

    /// @notice The Liquidity Gauge contract.
    ILiquidityGauge public gauge;

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

    /// @notice Modifier to mock the gauge to not be shutdown on the old strategy.
    modifier whenGaugeIsNotShutdownOnOldStrategy() {
        vm.mockCall(
            address(OLD_STRATEGY),
            abi.encodeWithSelector(IStrategy.isShutdown.selector, address(gauge)),
            abi.encode(false)
        );

        _;
    }

    constructor(uint256 _pid) {
        pid = _pid;
    }

    function setUp() public virtual {
        vm.createSelectFork("mainnet", 22_044_945);

        /// Get the LP token and base reward pool from Convex
        (address _lpToken,, address _gauge,,,) = BOOSTER.poolInfo(pid);

        lpToken = _lpToken;
        gauge = ILiquidityGauge(_gauge);
        totalSupply = IBalanceProvider(lpToken).totalSupply();

        _setup(CRV, lpToken, LOCKER, PROTOCOL_ID, false);

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

        /// 5. Enable Strategy as Module in Gateway.
        _enableModule(address(curveStrategy));

        /// 6. Allow minting of the reward token.
        _allowMint(address(curveStrategy));

        /// 6. Enable Factory as Module in Gateway.
        _enableModule(address(curveFactory));

        /// 7. Clear the locker from any balance of the gauge and reward token.
        _clearLocker();

        /// 8. By default, all the gauges are considered shutdown on the old strategy.
        vm.mockCall(
            address(OLD_STRATEGY),
            abi.encodeWithSelector(IStrategy.isShutdown.selector, address(gauge)),
            abi.encode(true)
        );
    }

    ///////////////////////////////////////////////////////////////////////////
    //// - HELPERS
    ///////////////////////////////////////////////////////////////////////////

    /// @notice Enable a module in the Gateway.
    function _enableModule(address _module) internal {
        gateway.execTransaction(
            address(gateway),
            0,
            abi.encodeWithSelector(IModuleManager.enableModule.selector, _module),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signatures
        );
    }

    //
    function _disableModule(address _module) internal {
        gateway.execTransaction(
            address(gateway),
            0,
            abi.encodeWithSelector(IModuleManager.disableModule.selector, _module),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signatures
        );
    }

    /// @notice Clear the locker from any balance of the gauge and reward token.
    /// TODO: Clear extra rewards as well if needed.
    function _clearLocker() internal {
        // Create a burn address to send tokens to
        address burn = makeAddr("Burn");

        // Get current gauge balance in the locker
        uint256 balance = gauge.balanceOf(LOCKER);

        // 1. Withdraw LP tokens from gauge without claiming rewards
        bytes memory withdrawData = abi.encodeWithSignature("withdraw(uint256)", balance);
        bytes memory withdrawExecute =
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(gauge), 0, withdrawData);

        gateway.execTransaction(
            address(locker), 0, withdrawExecute, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), signatures
        );

        // 2. Transfer the LP tokens to burn address
        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", burn, balance);
        bytes memory transferExecute =
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(lpToken), 0, transferData);

        gateway.execTransaction(
            address(locker), 0, transferExecute, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), signatures
        );
    }

    function _allowMint(address minter) internal {
        bytes memory data = abi.encodeWithSignature("toggle_approve_mint(address)", minter);
        data = abi.encodeWithSignature("execute(address,uint256,bytes)", address(MINTER), 0, data);
        gateway.execTransaction(
            address(locker), 0, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), signatures
        );
    }

    function _inflateRewards(address gauge) internal returns (uint256 inflation) {
        inflation = 1_000_000e18;
        vm.mockCall(
            address(gauge),
            abi.encodeWithSelector(ILiquidityGauge.integrate_fraction.selector, address(LOCKER)),
            abi.encode(inflation)
        );
    }
}
