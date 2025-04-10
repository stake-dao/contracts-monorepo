// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";
import {Router} from "src/Router.sol";
import {RouterBaseTest} from "./RouterBaseTest.t.sol";

contract Router__setModule is RouterBaseTest {
    function setModule(uint8 identifier, address _module) internal virtual {
        router.setModule(identifier, _module);
    }

    function test_RevertsIfTheCallerIsNotTheOwner(address caller) external {
        // it reverts if the caller is not the owner

        vm.assume(caller != owner);
        vm.label(caller, "caller");

        // expect the OwnableUnauthorizedAccount error to be reverted
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));

        // prank the caller and set the module
        vm.prank(caller);
        setModule(uint8(0x01), makeAddr("module"));
    }

    function test_SetsTheModuleAtTheCorrectLocation(uint8 identifier) external {
        // it sets the module at the correct location

        // calculate the expected location of the module
        bytes32 buffer = router.getStorageBuffer();
        bytes32 expectedLocation = bytes32(uint256(buffer) + uint256(identifier));

        // set the module
        _prankOwner();
        setModule(identifier, address(module));

        // assert the module is set at the correct location
        bytes32 storageSlotValue = vm.load(address(router), expectedLocation);
        assertEq(storageSlotValue, bytes32(uint256(uint160(address(module)))));
    }

    function test_EmitsAModuleSetEvent(uint8 identifier, string memory moduleName) external {
        // it emits a ModuleSet event

        // mock the module name to the fuzzed value
        vm.mockCall(address(module), abi.encodeWithSelector(IRouterModule.name.selector), abi.encode(moduleName));

        // expect the ModuleSet event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Router.ModuleSet(identifier, address(module), moduleName);

        // set the module
        _prankOwner();
        setModule(identifier, address(module));
    }
}
