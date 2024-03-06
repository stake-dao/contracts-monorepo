// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {FxsCollector} from "src/frax/fxs/collector/FxsCollector.sol";
import {sdToken} from "src/base/token/sdToken.sol";

contract FxsCollectorTest is Test {
    FxsCollector internal collector;

    address internal constant INITIAL_DELEGATE = address(0xABBA);
    address internal constant GOVERNANCE = address(0xABCD);
    address internal constant DELEGATION_REGISTRY = 0x4392dC16867D53DBFE227076606455634d4c2795;
    address internal constant FXS = 0xFc00000000000000000000000000000000000002;

    sdToken internal sdFxs;
    address internal constant FXS_DEPOSITOR = address(0xACBAD);
    address internal constant SDFXS_GAUGE = address(0xABBACD);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("fraxtal"));
        vm.selectFork(forkId);

        sdFxs = new sdToken("dummy token", "DT");
        collector = new FxsCollector(GOVERNANCE, DELEGATION_REGISTRY, INITIAL_DELEGATE);
    }

    function test_collector_deploy() public {
        assertEq(collector.governance(), GOVERNANCE);
        assertEq(collector.futureGovernance(), address(0));
        assertEq(keccak256(abi.encode(collector.FXS())), keccak256(abi.encode(FXS)));
        assertEq(uint256(collector.currentPhase()), uint256(FxsCollector.Phase.Collect));
        assertEq(address(collector.sdFxs()), address(0));
        assertEq(address(collector.fxsDepositor()), address(0));
    }

    function test_revert_on_rescue() public {
        vm.expectRevert(FxsCollector.DifferentPhase.selector);
        collector.rescueFXS(address(this));
    }

    function test_revert_on_claim() public {
        vm.expectRevert(FxsCollector.DifferentPhase.selector);
        collector.claimSdFxs(address(this), false);
    }

    function test_mint_sdFxs() public {
        vm.prank(GOVERNANCE);
        collector.mintSdFxs(address(sdFxs), FXS_DEPOSITOR, SDFXS_GAUGE, address(this));
        assertEq(keccak256(abi.encode(collector.sdFxs())), keccak256(abi.encode(address(sdFxs))));
        assertEq(keccak256(abi.encode(collector.fxsDepositor())), keccak256(abi.encode(FXS_DEPOSITOR)));
        assertEq(keccak256(abi.encode(collector.sdFxsGauge())), keccak256(abi.encode(SDFXS_GAUGE)));
        // the FXS balance is zero so it remains in Collect phase
        assertEq(uint256(collector.currentPhase()), uint256(FxsCollector.Phase.Collect));
    }

    function test_toggle_rescue_phase() public {
        vm.prank(GOVERNANCE);
        collector.toggleRescuePhase();
        assertEq(uint256(collector.currentPhase()), uint256(FxsCollector.Phase.Rescue));
    }
}
