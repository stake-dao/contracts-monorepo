pragma solidity 0.8.28;

import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__metadata is RewardVaultBaseTest {
    function test_returnsTheCorrectName() external view {
        // it returns the correct name

        assertEq(rewardVault.name(), "Stake DAO Curve DAO Token Vault");
    }

    function test_returnsTheCorrectSymbol() external view {
        // it returns the correct symbol

        assertEq(rewardVault.symbol(), "sd-CRV-vault");
    }
}
