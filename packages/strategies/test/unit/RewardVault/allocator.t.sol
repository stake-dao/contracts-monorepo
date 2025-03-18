pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

contract RewardVault__allocator is RewardVaultBaseTest {
    function test_ReturnsTheAllocatorAssociatedWithTheVault(address allocator) external {
        // it returns the allocator associated with the vault

        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.allocator.selector),
            abi.encode(allocator)
        );

        assertEq(address(rewardVault.allocator()), allocator);
    }
}
