pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__previewWithdraw is RewardVaultBaseTest {
    function test_ReturnsTheProvidedAmountDueTo1To1Relationship(uint256 assets) external view {
        // it returns the provided amount due to 1 to 1 relationship

        assertEq(rewardVault.previewRedeem(assets), assets);
    }
}
