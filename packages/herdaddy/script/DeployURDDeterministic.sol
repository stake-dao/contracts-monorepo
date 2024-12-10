// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";
import "forge-std/src/Script.sol";

import {UniversalRewardsDistributor} from "src/distributors/UniversalRewardDistributor.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32, bytes memory) external;
}

contract Deploy is Script, Test {
    address deployer = 0x8898502BA35AB64b3562aBC509Befb7Eb178D4df;

    function run() public {
        vm.createSelectFork("polygon");
        vm.startBroadcast(deployer);

        ImmutableCreate2Factory factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

        bytes32 initalizeCode = keccak256(
            abi.encodePacked(
                type(UniversalRewardsDistributor).creationCode, abi.encode(deployer, 0, bytes32(0), bytes32(0))
            )
        );
        console.logBytes32(initalizeCode);

        address expectedAddress = 0x000000006feeE0b7a0564Cd5CeB283e10347C4Db;
        bytes32 salt = bytes32(0x8898502ba35ab64b3562abc509befb7eb178d4dfaf00585136c2c3020bd9fcd4);
        _deployMerkleDistributor(factory, salt, expectedAddress);

        vm.stopBroadcast();
    }

    function _deployMerkleDistributor(ImmutableCreate2Factory factory, bytes32 salt, address expectedAddress)
        internal
    {
        factory.safeCreate2(
            salt,
            abi.encodePacked(
                type(UniversalRewardsDistributor).creationCode, abi.encode(deployer, 0, bytes32(0), bytes32(0))
            )
        );

        UniversalRewardsDistributor distributor = UniversalRewardsDistributor(address(expectedAddress));

        if (address(distributor.owner()) != deployer) revert("NOPE");
    }
}
