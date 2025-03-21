pragma solidity 0.8.28;

import {Accountant} from "src/Accountant.sol";
import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__totalAssets is RewardVaultBaseTest {
    function test_ReturnsTheTotalSupplyInTheAccountant(uint128 totalSupply) external {
        // it returns the total supply in the accountant

        vm.mockCall(
            address(accountant), abi.encodeWithSelector(Accountant.totalSupply.selector), abi.encode(totalSupply)
        );

        assertEq(rewardVault.totalSupply(), totalSupply);
    }
}
