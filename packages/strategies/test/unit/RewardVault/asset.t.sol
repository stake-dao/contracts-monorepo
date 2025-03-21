pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RewardVault} from "src/RewardVault.sol";
import {RewardVaultBaseTest, BaseTest} from "test/RewardVaultBaseTest.sol";

contract RewardVault__asset is RewardVaultBaseTest {
    function test_ReturnsTheImmutableAssetPassedToTheClone(address asset) external {
        // it returns the immutable asset passed to the clone

        CloneFactoryRewardVaultTest cloneFactory = new CloneFactoryRewardVaultTest();
        address cloneRewardVault = cloneFactory.deployClone(address(rewardVault), makeAddr("gauge"), asset);

        assertEq(RewardVault(cloneRewardVault).asset(), asset);
    }
}

contract CloneFactoryRewardVaultTest is BaseTest {
    function deployClone(address implementation, address gauge, address asset) external returns (address) {
        // The asset() function reads from offset 40, so we need to ensure asset is at that position
        // We use abi.encodePacked to ensure proper byte alignment
        bytes memory encodedData = abi.encodePacked(gauge, asset);

        return Clones.cloneWithImmutableArgs(implementation, encodedData);
    }
}
