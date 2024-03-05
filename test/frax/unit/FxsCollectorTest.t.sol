// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {FxsCollector} from "src/frax/fxs/collector/FxsCollector.sol";

contract FxsCollectorTest is Test {
    FxsCollector internal collector;

    address internal constant INITIAL_DELEGATE = address(0xABBA);
    address internal constant GOVERNANCE = address(0xABCD);
    address internal constant DELEGATION_REGISTRY = 0x4392dC16867D53DBFE227076606455634d4c2795;
    address internal constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("fraxtal"));
        vm.selectFork(forkId);

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
        collector.claimSdFxs(address(this));
    }

    function test_revert_on_mint() public {
        vm.prank(GOVERNANCE);
        vm.expectRevert(FxsCollector.DifferentPhase.selector);
        collector.mintSdFxs(address(this));
    }

    function test_toggle_phase() public {
        vm.prank(GOVERNANCE);
        collector.togglePhase(FxsCollector.Phase.Rescue);
        assertEq(uint256(collector.currentPhase()), uint256(FxsCollector.Phase.Rescue));
    }

    function test_trigger_mint_phase() public {
        address sdFxs = address(0xABBAB);
        address fxsDepositor = address(0xAFFAF);
        vm.prank(GOVERNANCE);
        collector.triggerMintPhase(sdFxs, fxsDepositor);
        assertEq(keccak256(abi.encode(collector.sdFxs())), keccak256(abi.encode(sdFxs)));
        assertEq(keccak256(abi.encode(collector.fxsDepositor())), keccak256(abi.encode(fxsDepositor)));
        assertEq(uint256(collector.currentPhase()), uint256(FxsCollector.Phase.Mint));
    }
}
