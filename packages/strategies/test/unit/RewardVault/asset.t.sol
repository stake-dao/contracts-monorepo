pragma solidity 0.8.28;

import {RewardVaultBaseTest, BaseTest} from "test/RewardVaultBaseTest.sol";
import {RewardVault} from "src/RewardVault.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

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
        // The asset() function reads from offset 80, so we need to ensure asset is at that position
        // We use abi.encodePacked to ensure proper byte alignment
        // TODO: What's the purpose of the buffer?
        bytes memory encodedData = abi.encodePacked(makeAddr("buffer"), makeAddr("buffer"), gauge, asset);

        return Clones.cloneWithImmutableArgs(implementation, encodedData);
    }
}
