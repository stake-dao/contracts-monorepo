// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {stdStorage, StdStorage} from "forge-std/src/Test.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";

contract ProtocolController__registerVault is ProtocolControllerBaseTest {
    using stdStorage for StdStorage;

    address internal registrar;

    function setUp() public override {
        super.setUp();

        registrar = makeAddr("registrar");

        // set a valid registrar with calling the setter
        _cheat_override_storage(
            address(protocolController),
            "registrar(address)",
            bytes32(abi.encode(true)),
            bytes32(uint256(uint160(registrar)))
        );
    }

    function test_RevertsIfTheGaugeIsTheZeroAddress() external {
        // it reverts if the gauge is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);
        vm.prank(registrar);
        protocolController.registerVault(
            address(0), makeAddr("vault"), makeAddr("asset"), makeAddr("rewardReceiver"), vm.randomBytes4()
        );
    }

    function test_RevertsIfTheVaultIsTheZeroAddress() external {
        // it reverts if the vault is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);
        vm.prank(registrar);
        protocolController.registerVault(
            makeAddr("gauge"), address(0), makeAddr("asset"), makeAddr("rewardReceiver"), vm.randomBytes4()
        );
    }

    function test_RevertsIfTheAssetIsTheZeroAddress() external {
        // it reverts if the asset is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);
        vm.prank(registrar);
        protocolController.registerVault(
            makeAddr("gauge"), makeAddr("vault"), address(0), makeAddr("rewardReceiver"), vm.randomBytes4()
        );
    }

    function test_RevertsIfTheRewardReceiverIsTheZeroAddress() external {
        // it reverts if the reward receiver is the zero address

        vm.expectRevert(ProtocolController.ZeroAddress.selector);
        vm.prank(registrar);
        protocolController.registerVault(
            makeAddr("gauge"), makeAddr("vault"), makeAddr("asset"), address(0), vm.randomBytes4()
        );
    }

    function test_RevertsIfCallerIsNotTheRegistrar(address caller) external {
        // it reverts if caller is not the registrar

        vm.assume(caller != registrar);

        vm.expectRevert(ProtocolController.OnlyRegistrar.selector);
        vm.prank(caller);
        protocolController.registerVault(
            makeAddr("gauge"), makeAddr("vault"), makeAddr("asset"), makeAddr("rewardReceiver"), vm.randomBytes4()
        );
    }

    function test_RegistersAVaultForAGauge(
        address gauge,
        address vault,
        address asset,
        address rewardReceiver,
        bytes4 protocolId
    ) external {
        // it registers a vault for a gauge

        vm.assume(gauge != address(0));
        vm.assume(vault != address(0));
        vm.assume(asset != address(0));
        vm.assume(rewardReceiver != address(0));
        vm.assume(protocolId != bytes4(0));

        // register the vault
        vm.prank(registrar);
        protocolController.registerVault(gauge, vault, asset, rewardReceiver, protocolId);

        // check the state of the gauge is correct
        (
            address $vault,
            address $asset,
            address $rewardReceiver,
            bytes4 $protocolId,
            bool $isShutdown,
            bool $isFullyWithdrawn
        ) = protocolController.gauge(gauge);
        assertEq($vault, vault);
        assertEq($asset, asset);
        assertEq($rewardReceiver, rewardReceiver);
        assertEq($protocolId, protocolId);
        assertEq($isShutdown, false);
        assertEq($isFullyWithdrawn, false);
    }

    function test_EmitsAVaultRegisteredEvent(
        address gauge,
        address vault,
        address asset,
        address rewardReceiver,
        bytes4 protocolId
    ) external {
        // it emits a VaultRegistered event

        vm.assume(gauge != address(0));
        vm.assume(vault != address(0));
        vm.assume(asset != address(0));
        vm.assume(rewardReceiver != address(0));
        vm.assume(protocolId != bytes4(0));

        vm.expectEmit(true, true, true, true);
        emit ProtocolController.VaultRegistered(gauge, vault, asset, rewardReceiver, protocolId);

        vm.prank(registrar);
        protocolController.registerVault(gauge, vault, asset, rewardReceiver, protocolId);
    }
}
