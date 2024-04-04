// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {FxsCollector} from "src/frax/fxs/collector/FxsCollector.sol";
import {sdToken} from "src/base/token/sdToken.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {MockFxsDepositor, MockSdFxsGauge} from "test/frax/mocks/Mocks.sol";
import {Constants} from "src/base/utils/Constants.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import "test/utils/Utils.sol";

interface IDelegationRegistry {
    function delegationsOf(address _delgator) external view returns (address);

    function selfManagingDelegations(address _delegator) external view returns (bool);
}

contract FxsCollectorIntegrationTest is Test {
    FxsCollector internal collector;

    address internal constant INITIAL_DELEGATE = address(0xABBA);
    address internal constant GOVERNANCE = address(0xABCD);
    address internal constant DELEGATION_REGISTRY = 0x4392dC16867D53DBFE227076606455634d4c2795;
    ERC20 internal constant FXS = ERC20(0xFc00000000000000000000000000000000000002);

    ILiquidityGauge internal liquidityGaugeCollector;
    sdToken internal sdFxs;
    MockFxsDepositor internal fxsDepositor;
    MockSdFxsGauge internal sdFxsGauge;

    address internal constant USER_1 = address(0xAAAA);
    address internal constant USER_2 = address(0xBBBB);
    address internal constant CLAIMER = address(0xCABA);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("fraxtal"));
        vm.selectFork(forkId);

        sdFxs = new sdToken("stake dao sdFXS", "sdFXS");
        fxsDepositor = new MockFxsDepositor(address(sdFxs));
        sdFxs.setOperator(address(fxsDepositor));
        sdFxsGauge = new MockSdFxsGauge(address(sdFxs));

        collector = new FxsCollector(GOVERNANCE, DELEGATION_REGISTRY, INITIAL_DELEGATE);

        liquidityGaugeCollector = ILiquidityGauge(
            Utils.deployBytecode(
                Constants.LGV4_STRAT_FRAXTAL_BYTECODE,
                abi.encode(
                    address(collector),
                    address(this),
                    address(collector),
                    CLAIMER,
                    DELEGATION_REGISTRY,
                    INITIAL_DELEGATE
                )
            )
        );

        vm.prank(GOVERNANCE);
        collector.setCollectorGauge(address(liquidityGaugeCollector));

        deal(address(FXS), USER_1, 10e18);
        deal(address(FXS), USER_2, 10e18);
    }

    function test_delegation_registry() public {
        // collector
        assertEq(IDelegationRegistry(DELEGATION_REGISTRY).delegationsOf(address(collector)), INITIAL_DELEGATE);
        assertEq(IDelegationRegistry(DELEGATION_REGISTRY).selfManagingDelegations(address(collector)), false);

        // collector gauge
        assertEq(
            IDelegationRegistry(DELEGATION_REGISTRY).delegationsOf(address(liquidityGaugeCollector)), INITIAL_DELEGATE
        );
        assertEq(
            IDelegationRegistry(DELEGATION_REGISTRY).selfManagingDelegations(address(liquidityGaugeCollector)), false
        );
    }

    function test_collect_phase() public {
        uint256 amountToDeposit = 10e18;

        _depositFXS(USER_1, amountToDeposit, USER_1);
        _depositFXS(USER_2, amountToDeposit / 2, USER_2);

        assertEq(FXS.balanceOf(address(collector)), amountToDeposit + amountToDeposit / 2);

        assertEq(collector.balanceOf(USER_1), 0);
        assertEq(collector.balanceOf(USER_2), 0);
        assertEq(collector.balanceOf(address(liquidityGaugeCollector)), amountToDeposit + amountToDeposit / 2);
    }

    function test_collect_phase_recipient() public {
        uint256 amountToDeposit = 10e18;

        _depositFXS(USER_1, amountToDeposit, USER_2);

        assertEq(FXS.balanceOf(address(collector)), amountToDeposit);
        assertEq(liquidityGaugeCollector.balanceOf(USER_1), 0);
        assertEq(liquidityGaugeCollector.balanceOf(USER_2), amountToDeposit);
    }

    function test_claim_phase() public {
        uint256 amountToDeposit = 10e18;

        _depositFXS(USER_1, amountToDeposit, USER_1);
        _depositFXS(USER_2, amountToDeposit / 2, USER_2);

        vm.prank(GOVERNANCE);
        collector.mintSdFXS(address(sdFxs), address(fxsDepositor), address(sdFxsGauge), address(this));
        assertEq(uint256(collector.currentPhase()), uint256(FxsCollector.Phase.Claim));
        assertEq(sdFxs.balanceOf(address(collector)), amountToDeposit + amountToDeposit / 2);

        vm.prank(USER_1);
        collector.claimSdFXS(USER_1, false); // receive sdFxs
        assertEq(sdFxs.balanceOf(USER_1), amountToDeposit);

        vm.prank(USER_2);
        collector.claimSdFXS(USER_2, true); // receive sdFxs-gauge
        assertEq(sdFxs.balanceOf(USER_2), 0);
        assertEq(sdFxs.balanceOf(address(sdFxsGauge)), amountToDeposit / 2);
        assertEq(sdFxsGauge.balanceOf(USER_2), amountToDeposit / 2);

        assertEq(sdFxs.balanceOf(address(collector)), 0);
    }

    function test_mint_incentive() public {
        uint256 amountToDeposit = 10e18;
        uint256 incentiveToken = 1e18;

        _depositFXS(USER_1, amountToDeposit, USER_1);

        fxsDepositor.setIncentiveToken(incentiveToken);
        vm.prank(GOVERNANCE);
        collector.mintSdFXS(address(sdFxs), address(fxsDepositor), address(sdFxsGauge), address(this));

        assertEq(sdFxs.balanceOf(address(collector)), amountToDeposit);
        assertEq(sdFxs.balanceOf(address(this)), incentiveToken);
    }

    function test_rescue_phase() public {
        uint256 amountToDeposit = 10e18;

        _depositFXS(USER_1, amountToDeposit, USER_1);
        _depositFXS(USER_2, amountToDeposit / 2, USER_2);

        vm.prank(GOVERNANCE);
        collector.toggleRescuePhase();
        assertEq(uint256(collector.currentPhase()), uint256(FxsCollector.Phase.Rescue));

        uint256 user1Balance = FXS.balanceOf(USER_1);
        vm.prank(USER_1);
        collector.rescueFXS(USER_1);
        vm.prank(USER_2);
        collector.rescueFXS(address(this));

        assertEq(liquidityGaugeCollector.balanceOf(USER_1), 0);
        assertEq(liquidityGaugeCollector.balanceOf(USER_2), 0);
        assertEq(FXS.balanceOf(address(collector)), 0);

        assertEq(FXS.balanceOf(address(this)), amountToDeposit / 2);
        assertEq(FXS.balanceOf(USER_1) - user1Balance, amountToDeposit);
    }

    function _depositFXS(address _user, uint256 _amountToDeposit, address _recipient) internal {
        vm.startPrank(_user);
        ERC20(FXS).approve(address(collector), _amountToDeposit);
        collector.depositFXS(_amountToDeposit, _recipient);
        vm.stopPrank();
    }
}
