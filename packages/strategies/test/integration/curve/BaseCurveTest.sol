// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IStrategy as IStakeDaoStrategy} from "@interfaces/stake-dao/IStrategy.sol";
import {ILiquidityGauge} from "@interfaces/curve/ILiquidityGauge.sol";
import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {Enum} from "@safe/contracts/common/Enum.sol";
import {CurveLocker, CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {ConvexSidecar} from "src/integrations/curve/ConvexSidecar.sol";
import {ConvexSidecarFactory, IBooster} from "src/integrations/curve/ConvexSidecarFactory.sol";
import {CurveFactory} from "src/integrations/curve/CurveFactory.sol";
import {CurveStrategy, IMinter} from "src/integrations/curve/CurveStrategy.sol";
import {IBalanceProvider} from "src/interfaces/IBalanceProvider.sol";
import {BaseSetup} from "test/BaseSetup.sol";

abstract contract BaseCurveTest is BaseSetup {
    ///////////////////////////////////////////////////////////////////////////
    //// - CONSTANTS
    ///////////////////////////////////////////////////////////////////////////

    /// @notice The protocol ID.
    bytes4 internal constant PROTOCOL_ID = bytes4(keccak256("CURVE"));

    /// @notice The reward token.
    address internal constant CRV = CurveProtocol.CRV;

    /// @notice The CVX token.
    address internal constant CVX = CurveProtocol.CONVEX_TOKEN;

    /// @notice The minter contract.
    address internal constant MINTER = CurveProtocol.MINTER;

    /// @notice The locker.
    address internal constant LOCKER = CurveLocker.LOCKER;

    /// @notice The Boost Delegation V3 contract.
    address public constant BOOST_DELEGATION_V3 = CurveProtocol.VE_BOOST;

    /// @notice The Convex Boost Holder contract.
    address public constant CONVEX_BOOST_HOLDER = CurveProtocol.CONVEX_PROXY;

    /// @notice The Booster contract.
    IBooster public constant BOOSTER = IBooster(CurveProtocol.CONVEX_BOOSTER);

    /// @notice The old strategy.
    address public constant OLD_STRATEGY = CurveLocker.STRATEGY;

    ///////////////////////////////////////////////////////////////////////////
    //// - HELPER STORAGE
    ///////////////////////////////////////////////////////////////////////////

    /// @notice The signature for the Safe transaction.
    bytes internal signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

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
            abi.encodeWithSelector(IStakeDaoStrategy.isShutdown.selector, address(gauge)),
            abi.encode(false)
        );
        vm.mockCall(
            address(OLD_STRATEGY),
            abi.encodeWithSelector(IStakeDaoStrategy.rewardDistributors.selector, address(gauge)),
            abi.encode(makeAddr("RewardDistributor"))
        );
        _;
    }

    constructor(uint256 _pid) {
        pid = _pid;
    }

    function setUp() public virtual {
        vm.createSelectFork("mainnet", 22_316_395);

        /// Get the LP token and base reward pool from Convex
        (address _lpToken,, address _gauge,,,) = BOOSTER.poolInfo(pid);

        lpToken = _lpToken;
        gauge = ILiquidityGauge(_gauge);
        totalSupply = IBalanceProvider(lpToken).totalSupply();

        _beforeSetup(CRV, LOCKER, PROTOCOL_ID, IStrategy.HarvestPolicy.CHECKPOINT);

        /// 1. Deploy the Curve Strategy contract.
        curveStrategy = new CurveStrategy(address(protocolController), LOCKER, address(gateway), MINTER);

        /// 2. Deploy the Convex Sidecar contract.
        convexSidecarImplementation = new ConvexSidecar(
            address(accountant), address(protocolController), CurveProtocol.CONVEX_TOKEN, CurveProtocol.CONVEX_BOOSTER
        );

        /// 3. Deploy the Convex Sidecar Factory contract.
        convexSidecarFactory = new ConvexSidecarFactory(
            address(convexSidecarImplementation), address(protocolController), CurveProtocol.CONVEX_BOOSTER
        );

        /// 2. Deploy the Curve Factory contract.
        curveFactory = new CurveFactory(
            CurveProtocol.GAUGE_CONTROLLER,
            CurveProtocol.CONVEX_TOKEN,
            CurveLocker.STRATEGY,
            CurveProtocol.CONVEX_BOOSTER,
            address(protocolController),
            address(rewardVaultImplementation),
            address(rewardReceiverImplementation),
            LOCKER,
            address(gateway),
            address(convexSidecarFactory)
        );

        /// 3. Setup the strategy in the protocol controller.
        protocolController.setStrategy(PROTOCOL_ID, address(curveStrategy));

        /// 4. Setup the factory in the protocol controller.
        protocolController.setRegistrar(address(curveFactory), true);
        protocolController.setRegistrar(address(convexSidecarFactory), true);

        /// 5. Enable Strategy as Module in Gateway.
        _enableModule(address(curveStrategy));

        /// 6. Allow minting of the reward token.
        _allowMint(address(curveStrategy));

        /// 6. Enable Factory as Module in Gateway.
        _enableModule(address(curveFactory));

        /// 7. Clear the locker from any balance of the gauge and reward token.
        _clearLocker();

        /// 8. By default, all the gauges are considered shutdown on the old strategy.
        _setupGauge(address(gauge));
    }

    ///////////////////////////////////////////////////////////////////////////
    //// - HELPERS
    ///////////////////////////////////////////////////////////////////////////

    /// @notice Set up a gauge with the needed mocks
    /// @param _gauge The address of the gauge to set up
    function _setupGauge(address _gauge) internal {
        // Mark the gauge as shutdown in the old strategy
        vm.mockCall(
            address(OLD_STRATEGY),
            abi.encodeWithSelector(IStakeDaoStrategy.isShutdown.selector, _gauge),
            abi.encode(true)
        );

        // Clear any existing balance in the gauge if needed
        if (ILiquidityGauge(_gauge).balanceOf(LOCKER) > 0) {
            _clearGaugeBalance(_gauge);
        }
    }

    /// @notice Clear the locker from any balance of a specific gauge
    /// @param _gauge The address of the gauge to clear
    function _clearGaugeBalance(address _gauge) internal {
        // Create a burn address to send tokens to
        address burn = makeAddr("Burn");

        // Get current gauge balance in the locker
        uint256 balance = ILiquidityGauge(_gauge).balanceOf(LOCKER);
        if (balance == 0) return;

        // Get the LP token for this gauge
        address _lpToken = ILiquidityGauge(_gauge).lp_token();

        // 1. Withdraw LP tokens from gauge without claiming rewards
        bytes memory withdrawData = abi.encodeWithSignature("withdraw(uint256)", balance);
        bytes memory withdrawExecute =
            abi.encodeWithSignature("execute(address,uint256,bytes)", _gauge, 0, withdrawData);

        gateway.execTransaction(
            address(locker), 0, withdrawExecute, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), signatures
        );

        // 2. Transfer the LP tokens to burn address
        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", burn, balance);
        bytes memory transferExecute =
            abi.encodeWithSignature("execute(address,uint256,bytes)", _lpToken, 0, transferData);

        gateway.execTransaction(
            address(locker), 0, transferExecute, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), signatures
        );
    }

    /// @notice Clear the locker from any balance of the gauge and reward token.
    /// TODO: Clear extra rewards as well if needed.
    function _clearLocker() internal {
        // Use the new helper function to clear the gauge balance
        _clearGaugeBalance(address(gauge));
    }

    function _allowMint(address minter) internal {
        bytes memory data = abi.encodeWithSignature("toggle_approve_mint(address)", minter);
        data = abi.encodeWithSignature("execute(address,uint256,bytes)", address(MINTER), 0, data);
        gateway.execTransaction(
            address(locker), 0, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), signatures
        );
    }

    function _inflateRewards(address _gauge, uint256 inflation) internal returns (uint256) {
        // Get the current minted amount for LOCKER from the gauge
        uint256 minted = IMinter(MINTER).minted(LOCKER, _gauge);

        // Calculate what integrate_fraction should be to get exactly the inflation amount
        uint256 targetIntegrateFraction = minted + inflation;

        // Mock the integrate_fraction call to return our target value
        vm.mockCall(
            address(_gauge),
            abi.encodeWithSelector(ILiquidityGauge.integrate_fraction.selector, address(LOCKER)),
            abi.encode(targetIntegrateFraction)
        );

        // Return the expected rewards amount
        return inflation;
    }
}
