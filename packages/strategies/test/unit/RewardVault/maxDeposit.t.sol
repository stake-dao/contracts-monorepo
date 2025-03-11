pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__maxDeposit is RewardVaultBaseTest {
    function test_ReturnsTheMaxUint256(address token) external {
        // it returns the max uint256

        assertEq(rewardVault.maxDeposit(token), type(uint256).max);
    }
}
