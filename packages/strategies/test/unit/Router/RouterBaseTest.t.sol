// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";
import {Router} from "src/Router.sol";

contract RouterBaseTest is Test {
    address internal owner = makeAddr("owner");

    Router internal router;
    IRouterModule internal module;

    function setUp() external {
        vm.label(owner, "owner");

        // deploy the router with the owner
        vm.prank(owner);
        router = new Router();

        // deploy a simple mock module
        module = new ModuleMock();
    }

    function _prankOwner() internal {
        vm.prank(owner);
    }
}

contract ModuleMock is IRouterModule {
    string public name = "ModuleMock";
    string public version = "1.0.0";

    function action(address a, address b, uint256 c) external payable returns (uint256) {}

    function delegateCallOnly(address expectedDelegateCallCaller) external view returns (bool) {
        require(address(this) == expectedDelegateCallCaller, "ModuleMock: wrong caller");
        return true;
    }
}
