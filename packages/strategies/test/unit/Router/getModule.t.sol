// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {RouterBaseTest} from "./RouterBaseTest.t.sol";

contract Router__getModule is RouterBaseTest {
    function test_ReturnsTheModuleAtTheGivenIdentifier(uint8 identifier, address _module) external {
        // it returns the module at the given identifier

        bytes32 location = bytes32(uint256(router.getStorageBuffer()) + identifier);

        vm.store(address(router), location, bytes32(uint256(uint160(_module))));

        assertEq(router.getModule(identifier), _module);
    }

    function test_ReturnsAddress0IfTheModuleIsNotSet(uint8 identifier) external view {
        // it returns address(0) if the module is not set

        assertEq(router.getModule(identifier), address(0));
    }
}
