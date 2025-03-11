pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";

contract RewardVault__constructor is RewardVaultBaseTest {
    function test_RevertIfAccountantIsZeroAddress() external {
        // it revert if accountant is zero address

        vm.expectRevert(abi.encodeWithSelector(RewardVault.ZeroAddress.selector));
        new RewardVault(bytes4(0x11223344), makeAddr("protocolController"), address(0));
    }

    function test_RevertIfProtocolControllerIsZeroAddress() external {
        // it revert if protocolController is zero address

        vm.expectRevert(abi.encodeWithSelector(RewardVault.ZeroAddress.selector));
        new RewardVault(bytes4(0x11223344), address(0), makeAddr("accountant"));
    }

    function test_SetProtocolId(bytes4 protocolId) external {
        // it set protocolId

        RewardVault newVault = new RewardVault(protocolId, makeAddr("protocolController"), makeAddr("accountant"));

        assertEq(newVault.PROTOCOL_ID(), protocolId);
    }

    function test_SetAccountant() external {
        // it set accountant

        RewardVault newVault = new RewardVault(protocolId, makeAddr("protocolController"), makeAddr("accountant"));
        assertEq(address(newVault.ACCOUNTANT()), makeAddr("accountant"));
    }

    function test_SetProtocolController() external {
        // it set protocolController

        RewardVault newVault = new RewardVault(protocolId, makeAddr("protocolController"), makeAddr("accountant"));
        assertEq(address(newVault.PROTOCOL_CONTROLLER()), makeAddr("protocolController"));
    }
}
