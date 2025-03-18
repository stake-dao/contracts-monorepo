pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__maxMint is RewardVaultBaseTest {
    function test_ReturnsTheMaxUint256(address token) external view {
        // it returns the max uint256

        assertEq(rewardVault.maxMint(token), type(uint256).max);
    }
}
