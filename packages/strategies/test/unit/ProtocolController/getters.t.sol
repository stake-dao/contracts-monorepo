// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ProtocolController} from "src/ProtocolController.sol";
import {ProtocolControllerBaseTest} from "test/ProtocolControllerBaseTest.t.sol";
import {ProtocolControllerHarness} from "test/unit/ProtocolController/ProtocolControllerHarness.t.sol";

contract ProtocolController__getters is ProtocolControllerBaseTest {
    ProtocolControllerHarness internal protocolControllerHarness;
    bytes4 internal constant PROTOCOL_ID = bytes4(keccak256("convex"));

    function setUp() public override {
        super.setUp();

        protocolControllerHarness = _deployProtocolControllerHarness();
    }

    function test_ReturnsTheStrategyAddressForAProtocol(address strategy) external {
        // it returns the strategy address for a protocol

        vm.assume(strategy != address(0));

        protocolControllerHarness._cheat_override_protocol_components(
            PROTOCOL_ID,
            ProtocolController.ProtocolComponents({
                strategy: strategy,
                allocator: address(0),
                accountant: address(0),
                feeReceiver: address(0),
                isShutdown: false
            })
        );

        assertEq(protocolController.strategy(PROTOCOL_ID), strategy);
    }

    function test_ReturnsTheAllocatorAddressForAProtocol(address allocator) external {
        // it returns the allocator address for a protocol

        vm.assume(allocator != address(0));

        protocolControllerHarness._cheat_override_protocol_components(
            PROTOCOL_ID,
            ProtocolController.ProtocolComponents({
                strategy: address(0),
                allocator: allocator,
                accountant: address(0),
                feeReceiver: address(0),
                isShutdown: false
            })
        );

        assertEq(protocolController.allocator(PROTOCOL_ID), allocator);
    }

    function test_ReturnsTheAccountantAddressForAProtocol(address accountant) external {
        // it returns the accountant address for a protocol

        vm.assume(accountant != address(0));

        protocolControllerHarness._cheat_override_protocol_components(
            PROTOCOL_ID,
            ProtocolController.ProtocolComponents({
                strategy: address(0),
                allocator: address(0),
                accountant: accountant,
                feeReceiver: address(0),
                isShutdown: false
            })
        );

        assertEq(protocolController.accountant(PROTOCOL_ID), accountant);
    }

    function test_ReturnsTheFeeReceiverAddressForAProtocol(address feeReceiver) external {
        // it returns the fee receiver address for a protocol

        vm.assume(feeReceiver != address(0));

        protocolControllerHarness._cheat_override_protocol_components(
            PROTOCOL_ID,
            ProtocolController.ProtocolComponents({
                strategy: address(0),
                allocator: address(0),
                accountant: address(0),
                feeReceiver: feeReceiver,
                isShutdown: false
            })
        );

        assertEq(protocolController.feeReceiver(PROTOCOL_ID), feeReceiver);
    }

    function test_ReturnsIfAnAddressIsAnAuthorizedRegistrar(address registrar) external {
        // it returns if an address is an authorized registrar

        vm.assume(registrar != address(0));

        assertEq(protocolController.isRegistrar(registrar), false);
        _cheat_override_storage(
            address(protocolController), "registrar(address)", bytes32(abi.encode(true)), bytes32(abi.encode(registrar))
        );
        assertEq(protocolController.isRegistrar(registrar), true);
    }

    function test_ReturnsTheProtocolShutdownStatusForAProtocol(bool isShutdown) external {
        // it returns the protocol shutdown status for a protocol

        vm.assume(isShutdown != protocolController.isShutdownProtocol(PROTOCOL_ID));

        protocolControllerHarness._cheat_override_protocol_components(
            PROTOCOL_ID,
            ProtocolController.ProtocolComponents({
                strategy: address(0),
                allocator: address(0),
                accountant: address(0),
                feeReceiver: address(0),
                isShutdown: isShutdown
            })
        );

        assertEq(protocolController.isShutdownProtocol(PROTOCOL_ID), isShutdown);
    }

    function test_ReturnsTheVaultAddressForAGauge(address gauge, address vault) external {
        // it returns the vault address for a gauge

        vm.assume(gauge != address(0));
        vm.assume(vault != address(0));

        protocolControllerHarness._cheat_override_gauge(
            gauge,
            ProtocolController.Gauge({
                vault: vault,
                asset: address(0),
                rewardReceiver: address(0),
                protocolId: bytes4(0),
                isShutdown: false
            })
        );

        assertEq(protocolControllerHarness.vaults(gauge), vault);
    }

    function test_ReturnsTheRewardReceiverAddressForAGauge(address gauge, address rewardReceiver) external {
        // it returns the reward receiver address for a gauge

        vm.assume(gauge != address(0));
        vm.assume(rewardReceiver != address(0));

        protocolControllerHarness._cheat_override_gauge(
            gauge,
            ProtocolController.Gauge({
                vault: address(0),
                asset: address(0),
                rewardReceiver: rewardReceiver,
                protocolId: bytes4(0),
                isShutdown: false
            })
        );

        assertEq(protocolControllerHarness.rewardReceiver(gauge), rewardReceiver);
    }

    function test_ReturnsTheAssetAddressForAGauge(address gauge, address asset) external {
        // it returns the asset address for a gauge

        vm.assume(gauge != address(0));
        vm.assume(asset != address(0));

        protocolControllerHarness._cheat_override_gauge(
            gauge,
            ProtocolController.Gauge({
                vault: address(0),
                asset: asset,
                rewardReceiver: address(0),
                protocolId: bytes4(0),
                isShutdown: false
            })
        );

        assertEq(protocolControllerHarness.asset(gauge), asset);
    }

    function test_ChecksIfACallerIsAllowedToCallAFunctionOnAContract(
        address caller,
        address contractAddress,
        bytes4 selector
    ) external {
        // it checks if a caller is allowed to call a function on a contract

        vm.assume(caller != address(0));
        vm.assume(contractAddress != address(0));

        // unregistered caller is not allowed to call any function on any contract
        assertEq(protocolController.allowed(contractAddress, caller, selector), false);

        // the owner is allowed to call any function on any contract
        assertEq(protocolController.allowed(contractAddress, owner, selector), true);

        // registered caller is allowed to call any function on the contract if the permission is set
        protocolControllerHarness._cheat_override_permissions(contractAddress, caller, selector, true);
        assertEq(protocolControllerHarness.allowed(contractAddress, caller, selector), true);
    }

    function test_ChecksIfAGaugeIsShutdown(bool isShutdown) external {
        // it checks if a gauge is shutdown

        protocolControllerHarness._cheat_override_protocol_components(
            PROTOCOL_ID,
            ProtocolController.ProtocolComponents({
                strategy: address(0),
                allocator: address(0),
                accountant: address(0),
                feeReceiver: address(0),
                isShutdown: isShutdown
            })
        );

        assertEq(protocolController.isShutdownProtocol(PROTOCOL_ID), isShutdown);
    }

    function test_ReturnsTheGaugeShutdownStatusForAGauge(address gauge) external {
        // it returns the gauge shutdown status for a gauge

        vm.assume(gauge != address(0));

        // 1. return `true` if the protocol is shutdown but not the gauge
        protocolControllerHarness._cheat_override_protocol_components(
            PROTOCOL_ID,
            ProtocolController.ProtocolComponents({
                strategy: address(0),
                allocator: address(0),
                accountant: address(0),
                feeReceiver: address(0),
                isShutdown: true
            })
        );
        protocolControllerHarness._cheat_override_gauge(
            gauge,
            ProtocolController.Gauge({
                vault: address(0),
                asset: address(0),
                rewardReceiver: address(0),
                protocolId: PROTOCOL_ID,
                isShutdown: false
            })
        );
        assertEq(protocolControllerHarness.isShutdown(gauge), true);

        // 2. return `true` if the gauge and the protocol are shutdown
        protocolControllerHarness._cheat_override_gauge(
            gauge,
            ProtocolController.Gauge({
                vault: address(0),
                asset: address(0),
                rewardReceiver: address(0),
                protocolId: PROTOCOL_ID,
                isShutdown: true
            })
        );
        assertEq(protocolControllerHarness.isShutdown(gauge), true);

        // 3. return `true` if the gauge is not shutdown but not the protocol
        protocolControllerHarness._cheat_override_protocol_components(
            PROTOCOL_ID,
            ProtocolController.ProtocolComponents({
                strategy: address(0),
                allocator: address(0),
                accountant: address(0),
                feeReceiver: address(0),
                isShutdown: false
            })
        );
        assertEq(protocolControllerHarness.isShutdown(gauge), true);

        // // 4. return `fale` if none of them are shutdown
        protocolControllerHarness._cheat_override_gauge(
            gauge,
            ProtocolController.Gauge({
                vault: address(0),
                asset: address(0),
                rewardReceiver: address(0),
                protocolId: PROTOCOL_ID,
                isShutdown: false
            })
        );
        assertEq(protocolControllerHarness.isShutdown(gauge), false);
    }
}
