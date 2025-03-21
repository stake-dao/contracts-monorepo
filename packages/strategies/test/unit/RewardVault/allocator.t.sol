pragma solidity 0.8.28;

import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

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
