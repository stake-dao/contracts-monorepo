pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__convertToAssets is RewardVaultBaseTest {
    function test_ReturnsTheProvidedAmountDueTo1To1Relationship(uint256 shares) external {
        // it returns the provided amount due to 1 to 1 relationship

        uint256 assets = rewardVault.convertToAssets(shares);
        assertEq(assets, shares);
    }
}
