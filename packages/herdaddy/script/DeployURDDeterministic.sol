// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";
import "forge-std/src/Script.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";
import {Common} from "address-book/src/CommonPolygon.sol";
import {UniversalRewardsDistributor} from "src/distributors/UniversalRewardDistributor.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32, bytes memory) external;
}

contract Deploy is Script, Test {
    address deployer = DAO.MAIN_DEPLOYER;

    function run() public {
        vm.createSelectFork("polygon");
        vm.startBroadcast(deployer);

        ImmutableCreate2Factory factory = ImmutableCreate2Factory(Common.CREATE2_FACTORY);

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
