// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {FxsCollector} from "src/frax/fxs/collector/FxsCollector.sol";
import {sdToken} from "src/base/token/sdToken.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {MockFxsDepositor, MockSdFxsGauge} from "test/frax/mocks/Mocks.sol";

contract FxsCollectorIntegrationTest is Test {
    FxsCollector internal collector;

    address internal constant INITIAL_DELEGATE = address(0xABBA);
    address internal constant GOVERNANCE = address(0xABCD);
    address internal constant DELEGATION_REGISTRY = 0x4392dC16867D53DBFE227076606455634d4c2795;
    ERC20 internal constant FXS = ERC20(0xFc00000000000000000000000000000000000002);

    sdToken internal sdFxs;
    MockFxsDepositor internal fxsDepositor;
    MockSdFxsGauge internal sdFxsGauge;

    address internal constant USER_1 = address(0xAAAA);
    address internal constant USER_2 = address(0xBBBB);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("fraxtal"));
        vm.selectFork(forkId);

        sdFxs = new sdToken("stake dao sdFXS", "sdFXS");
        fxsDepositor = new MockFxsDepositor(address(sdFxs));
        sdFxs.setOperator(address(fxsDepositor));
        sdFxsGauge = new MockSdFxsGauge(address(sdFxs));

        collector = new FxsCollector(GOVERNANCE, DELEGATION_REGISTRY, INITIAL_DELEGATE);

        deal(address(FXS), USER_1, 10e18);
        deal(address(FXS), USER_2, 10e18);
    }

    function test_collect_phase() public {
        uint256 amountToDeposit = 10e18;

        assertEq(collector.deposited(USER_1), 0);

        _depositFXS(USER_1, amountToDeposit);
        _depositFXS(USER_2, amountToDeposit / 2);

        assertEq(collector.deposited(USER_1), amountToDeposit);
        assertEq(collector.deposited(USER_2), amountToDeposit / 2);
        assertEq(FXS.balanceOf(address(collector)), amountToDeposit + amountToDeposit / 2);
    }

    function test_claim_phase() public {
        uint256 amountToDeposit = 10e18;

        _depositFXS(USER_1, amountToDeposit);
        _depositFXS(USER_2, amountToDeposit / 2);

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

    function test_rescue_phase() public {
        uint256 amountToDeposit = 10e18;

        _depositFXS(USER_1, amountToDeposit);
        _depositFXS(USER_2, amountToDeposit / 2);

        vm.prank(GOVERNANCE);
        collector.toggleRescuePhase();
        assertEq(uint256(collector.currentPhase()), uint256(FxsCollector.Phase.Rescue));

        uint256 user1Balance = FXS.balanceOf(USER_1);
        vm.prank(USER_1);
        collector.rescueFXS(USER_1);
        vm.prank(USER_2);
        collector.rescueFXS(address(this));

        assertEq(collector.deposited(USER_1), 0);
        assertEq(collector.deposited(USER_2), 0);
        assertEq(FXS.balanceOf(address(collector)), 0);

        assertEq(FXS.balanceOf(address(this)), amountToDeposit / 2);
        assertEq(FXS.balanceOf(USER_1) - user1Balance, amountToDeposit);
    }

    function _depositFXS(address _user, uint256 _amountToDeposit) internal {
        vm.startPrank(_user);
        ERC20(FXS).approve(address(collector), _amountToDeposit);
        collector.depositFXS(_amountToDeposit, _user);
        vm.stopPrank();
    }
}
