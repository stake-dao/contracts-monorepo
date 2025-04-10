// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {RouterBaseTest} from "./RouterBaseTest.t.sol";

contract Router__enumerateModules is RouterBaseTest {
    function test_ReturnsTheFullContiguousSequenceOfModules(uint8 length) external {
        // it returns the full contiguous sequence of modules

        // set the modules
        vm.startPrank(owner);
        for (uint8 i; i < length; i++) {
            router.setModule(i, address(module));
        }
        vm.stopPrank();

        // enumerate the modules
        bytes memory modules = router.enumerateModules();
        assertEq(modules.length, 20 * uint256(length));
    }

    function test_ReturnsAnEmptyArrayIfTheFirstSlotIsNotSet(uint8 length) external {
        // it returns an empty array if the first slot is not set

        // set the modules except the first slot
        vm.startPrank(owner);
        for (uint8 i = 1; i < uint256(length); i++) {
            router.setModule(i, address(module));
        }
        vm.stopPrank();

        // enumerate the modules
        bytes memory modules = router.enumerateModules();
        assertEq(modules.length, 0);
    }

    function test_ReturnsAnSubsetOfTheModulesIfThereIsAGapInTheSequence() external {
        // it returns an subset of the modules if there is a gap in the sequence

        // set the modules at the first 3 slots
        vm.startPrank(owner);
        for (uint8 i; i < 3; i++) {
            router.setModule(i, address(module));
        }
        vm.stopPrank();

        // set a new module at the 5th slot
        vm.startPrank(owner);
        router.setModule(uint8(5), address(module));
        vm.stopPrank();

        // enumerate the modules
        bytes memory modules = router.enumerateModules();
        assertEq(modules.length, 20 * 3);
    }
}
