pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__previewRedeem is RewardVaultBaseTest {
    function test_ReturnsTheProvidedAmountDueTo1To1Relationship(uint256 shares) external view {
        // it returns the provided amount due to 1 to 1 relationship

        assertEq(rewardVault.previewRedeem(shares), shares);
    }
}
