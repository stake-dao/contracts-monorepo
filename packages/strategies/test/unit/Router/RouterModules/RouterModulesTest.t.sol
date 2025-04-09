// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Router} from "src/Router.sol";
import {RewardVaultBaseTest} from "test/RewardVaultBaseTest.sol";

contract RouterModulesTest is RewardVaultBaseTest {
    address internal routerOwner;
    Router internal router;

    function setUp() public virtual override {
        super.setUp();

        routerOwner = makeAddr("router0wner");
        vm.prank(routerOwner);
        router = new Router();
    }

    function _cheat_setModule(uint8 identifier, address module) internal {
        vm.prank(routerOwner);
        router.setModule(identifier, module);
    }
}
