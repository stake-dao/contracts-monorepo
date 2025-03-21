pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {BaseTest} from "test/Base.t.sol";

contract RewardReceiver__rewardVault is BaseTest {
    RewardReceiver private clonedRewardReceiver;

    function test_ReturnsTheCorrectVaultAddress(address rewardVault) external {
        // it returns the correct vault address

        // clone the harnessed reward vault with the immutable variables
        clonedRewardReceiver =
            RewardReceiver(Clones.cloneWithImmutableArgs(address(new RewardReceiver()), abi.encodePacked(rewardVault)));

        assertEq(address(clonedRewardReceiver.rewardVault()), rewardVault);
    }
}
