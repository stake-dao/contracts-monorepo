// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Errors} from "@openzeppelin/contracts/utils/Address.sol";
import {Router} from "src/Router.sol";
import {RouterBaseTest, ModuleMock} from "./RouterBaseTest.t.sol";

contract Router__execute is RouterBaseTest {
    function test_RevertsIfOneOfTheModulesIsNotSet(uint8 correctIdentifier, uint8 incorrectIdentifier) external {
        // it reverts if one of the modules is not set

        vm.assume(correctIdentifier != incorrectIdentifier);

        // set the module at the first slot
        vm.startPrank(owner);
        router.setModule(correctIdentifier, address(module));
        vm.stopPrank();

        // construct the data for the correct module
        bytes memory dataModule1 = bytes.concat(
            bytes1(correctIdentifier),
            abi.encodeWithSelector(
                bytes4(keccak256("action(address,address,uint256)")),
                makeAddr("param1"),
                makeAddr("param2"),
                vm.randomUint()
            )
        );

        // construct the data for the incorrect module
        bytes memory dataModule2 = bytes.concat(
            bytes1(incorrectIdentifier),
            abi.encodeWithSelector(
                bytes4(keccak256("action(address,address,uint256)")),
                makeAddr("param1"),
                makeAddr("param2"),
                vm.randomUint()
            )
        );

        bytes[] memory calls = new bytes[](2);
        calls[0] = dataModule1;
        calls[1] = dataModule2;

        // expect the ModuleNotSet error to be reverted
        vm.expectRevert(abi.encodeWithSelector(Router.ModuleNotSet.selector, incorrectIdentifier));

        // execute the calls
        vm.prank(owner);
        router.execute(calls);
    }

    function test_RevertsIfOneOfTheCallsIsInvalid(uint8 correctIdentifier) external {
        // it reverts if one of the calls is invalid

        // set the module at the first slot
        vm.startPrank(owner);
        router.setModule(correctIdentifier, address(module));
        vm.stopPrank();

        // construct the valid data
        bytes memory dataModule1 = bytes.concat(
            bytes1(correctIdentifier),
            abi.encodeWithSelector(
                bytes4(keccak256("action(address,address,uint256)")),
                makeAddr("param1"),
                makeAddr("param2"),
                vm.randomUint()
            )
        );

        // construct the invalid data
        bytes memory dataModule2 = bytes.concat(
            bytes1(correctIdentifier),
            abi.encodeWithSelector(
                bytes4(keccak256("action_invalid(address,address,uint256)")),
                makeAddr("param1"),
                makeAddr("param2"),
                vm.randomUint()
            )
        );

        bytes[] memory calls = new bytes[](2);
        calls[0] = dataModule1;
        calls[1] = dataModule2;

        // expect the InvalidCall error to be reverted
        vm.expectRevert(abi.encodeWithSelector(Errors.FailedCall.selector));

        // execute the calls
        vm.prank(owner);
        router.execute(calls);
    }

    function test_RevertsIfOneOfTheCallsReverts() external {
        // it reverts if one of the calls reverts

        // set the module at the first slot
        vm.startPrank(owner);
        router.setModule(99, address(module));
        vm.stopPrank();

        // construct the valid data
        bytes memory dataModule1 = bytes.concat(
            bytes1(uint8(99)),
            abi.encodeWithSelector(
                bytes4(keccak256("action(address,address,uint256)")),
                makeAddr("param1"),
                makeAddr("param2"),
                vm.randomUint()
            )
        );
        bytes[] memory calls = new bytes[](1);
        calls[0] = dataModule1;

        // make the module revert
        vm.mockCallRevert(address(module), abi.encodeWithSelector(ModuleMock.action.selector), "REVERT_MESSAGE");
        vm.expectRevert("REVERT_MESSAGE");

        // execute the calls
        vm.prank(owner);
        router.execute(calls);
    }

    function test_ExecutesTheCallsAndReturnsTheResults() external {
        // it executes the calls and returns the results

        // deploy 4 different module
        ModuleMock module1 = new ModuleMock();
        ModuleMock module2 = new ModuleMock();
        ModuleMock module3 = new ModuleMock();
        ModuleMock module4 = new ModuleMock();

        // set the modules at 4 differents slots
        vm.startPrank(owner);
        router.setModule(0, address(module1));
        router.setModule(1, address(module2));
        router.setModule(9, address(module3));
        router.setModule(47, address(module4));
        vm.stopPrank();

        // construct the valid data for calling the 4 modules
        bytes memory dataModule1 = bytes.concat(
            bytes1(uint8(0)),
            abi.encodeWithSelector(
                bytes4(keccak256("action(address,address,uint256)")),
                makeAddr("param1"),
                makeAddr("param2"),
                vm.randomUint()
            )
        );

        // construct the data for the second module
        bytes memory dataModule2 = bytes.concat(
            bytes1(uint8(1)),
            abi.encodeWithSelector(
                bytes4(keccak256("action(address,address,uint256)")),
                makeAddr("param1"),
                makeAddr("param2"),
                vm.randomUint()
            )
        );

        // construct the data for the third module
        bytes memory dataModule3 = bytes.concat(
            bytes1(uint8(9)),
            abi.encodeWithSelector(
                bytes4(keccak256("action(address,address,uint256)")),
                makeAddr("param1"),
                makeAddr("param2"),
                vm.randomUint()
            )
        );

        // construct the data for the fourth module
        bytes memory dataModule4 = bytes.concat(
            bytes1(uint8(47)),
            abi.encodeWithSelector(
                bytes4(keccak256("action(address,address,uint256)")),
                makeAddr("param1"),
                makeAddr("param2"),
                vm.randomUint()
            )
        );

        // construct the calls array
        bytes[] memory calls = new bytes[](4);
        calls[0] = dataModule1;
        calls[1] = dataModule2;
        calls[2] = dataModule3;
        calls[3] = dataModule4;

        // mock the results of the modules
        uint256 expectedResult1 = 1e20;
        uint256 expectedResult2 = 1e9;
        uint256 expectedResult3 = 312_924;
        uint256 expectedResult4 = type(uint16).max;
        vm.mockCall(address(module1), abi.encodeWithSelector(ModuleMock.action.selector), abi.encode(expectedResult1));
        vm.mockCall(address(module2), abi.encodeWithSelector(ModuleMock.action.selector), abi.encode(expectedResult2));
        vm.mockCall(address(module3), abi.encodeWithSelector(ModuleMock.action.selector), abi.encode(expectedResult3));
        vm.mockCall(address(module4), abi.encodeWithSelector(ModuleMock.action.selector), abi.encode(expectedResult4));

        // execute the calls
        vm.prank(owner);
        bytes[] memory results = router.execute(calls);

        // assert the results
        assertEq(results[0], abi.encode(expectedResult1));
        assertEq(results[1], abi.encode(expectedResult2));
        assertEq(results[2], abi.encode(expectedResult3));
        assertEq(results[3], abi.encode(expectedResult4));
    }

    function test_ExecutesModulesWithDelegatecall() external {
        // it executes modules with delegatecall

        // set the module at the first slot
        vm.startPrank(owner);
        router.setModule(99, address(module));
        vm.stopPrank();

        // construct the data to call the `delegateCallOnly` function in the module
        bytes memory dataModule1 = bytes.concat(
            bytes1(uint8(99)), abi.encodeWithSelector(bytes4(keccak256("delegateCallOnly(address)")), address(router))
        );

        bytes[] memory calls = new bytes[](1);
        calls[0] = dataModule1;

        // execute the calls
        vm.prank(owner);
        bytes[] memory results = router.execute(calls);
        assertEq(results[0], abi.encode(true));
    }

    function test_ItCanReceiveEther(uint256 amount) external {
        // it can receive ether

        vm.deal(owner, amount);
        vm.prank(owner);
        router.execute{value: amount}(new bytes[](0));

        // assert the ether was received
        assertEq(address(router).balance, amount);
    }
}
