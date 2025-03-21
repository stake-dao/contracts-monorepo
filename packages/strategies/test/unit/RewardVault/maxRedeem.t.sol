pragma solidity 0.8.28;

import {Accountant} from "src/Accountant.sol";
import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__maxRedeem is RewardVaultBaseTest {
    function test_ReturnsTheBalanceOfTheOwner(uint128 balance, address owner) external {
        // it returns the balance of the owner

        vm.mockCall(address(accountant), abi.encodeWithSelector(Accountant.balanceOf.selector), abi.encode(balance));

        assertEq(rewardVault.maxRedeem(owner), balance);
    }
}
