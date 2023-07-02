// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Script.sol";

contract Deployer is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        console.log("Hello world");
    }
}
