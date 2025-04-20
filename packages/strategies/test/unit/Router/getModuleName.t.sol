// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IRouterModule} from "src/interfaces/IRouterModule.sol";
import {RouterBaseTest} from "./RouterBaseTest.t.sol";

contract Router__getModuleName is RouterBaseTest {
    function test_ReturnsTheNameOfTheModuleAtTheGivenIdentifier(uint8 identifier, string memory moduleName) external {
        // it returns the name of the module at the given identifier

        // set the module
        _prankOwner();
        router.setModule(identifier, address(module));

        // mock the module name to the fuzzed value
        vm.mockCall(address(module), abi.encodeWithSelector(IRouterModule.name.selector), abi.encode(moduleName));

        assertEq(router.getModuleName(identifier), moduleName);
    }

    function test_ReturnsAnEmptyStringIfTheModuleIsNotSet(uint8 identifier) external view {
        // it returns an empty string if the module is not set

        assertEq(router.getModuleName(identifier), "");
    }
}
