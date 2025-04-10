// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Router} from "src/Router.sol";
import {Router__setModule} from "test/unit/Router/setModule.t.sol";

contract Router__safeSetModule is Router__setModule {
    function setModule(uint8 identifier, address _module) internal override {
        router.safeSetModule(identifier, _module);
    }

    function test_ItActsAsSetModule() external {
        // don't need to test anything, we're using the same logic as the setModule test
        // keep this function for clarity and check using bulloak
    }

    function test_RevertsIfTheModuleIsAlreadySet(uint8 identifier) external {
        // it reverts if the module is already set

        // set the module
        _prankOwner();
        router.setModule(identifier, address(module));

        // try to set the module again
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Router.IdentifierAlreadyUsed.selector, identifier));
        setModule(identifier, address(module));
    }
}
