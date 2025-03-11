pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

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
