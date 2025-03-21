pragma solidity 0.8.28;

import {RewardVault} from "src/RewardVault.sol";
import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__constructor is RewardVaultBaseTest {
    function test_RevertIfAccountantIsZeroAddress() external {
        // it revert if accountant is zero address

        vm.expectRevert(abi.encodeWithSelector(RewardVault.ZeroAddress.selector));
        new RewardVault(bytes4(0x11223344), makeAddr("protocolController"), address(0), false);
    }

    function test_RevertIfProtocolControllerIsZeroAddress() external {
        // it revert if protocolController is zero address

        vm.expectRevert(abi.encodeWithSelector(RewardVault.ZeroAddress.selector));
        new RewardVault(bytes4(0x11223344), address(0), makeAddr("accountant"), false);
    }

    function test_SetProtocolId(bytes4 protocolId) external {
        // it set protocolId

        RewardVault newVault =
            new RewardVault(protocolId, makeAddr("protocolController"), makeAddr("accountant"), false);

        assertEq(newVault.PROTOCOL_ID(), protocolId);
    }

    function test_SetAccountant() external {
        // it set accountant

        RewardVault newVault =
            new RewardVault(protocolId, makeAddr("protocolController"), makeAddr("accountant"), false);
        assertEq(address(newVault.ACCOUNTANT()), makeAddr("accountant"));
    }

    function test_SetProtocolController() external {
        // it set protocolController

        RewardVault newVault =
            new RewardVault(protocolId, makeAddr("protocolController"), makeAddr("accountant"), false);
        assertEq(address(newVault.PROTOCOL_CONTROLLER()), makeAddr("protocolController"));
    }
}
