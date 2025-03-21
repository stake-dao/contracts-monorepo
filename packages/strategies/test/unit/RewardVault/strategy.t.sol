pragma solidity 0.8.28;

import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__strategy is RewardVaultBaseTest {
    function test_ReturnsTheStrategyAssociatedWithTheVault(address strategy) external {
        // it returns the strategy associated with the vault

        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.strategy.selector),
            abi.encode(strategy)
        );

        assertEq(address(rewardVault.strategy()), strategy);
    }
}
