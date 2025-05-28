// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DaoEthereum.sol";
import {Test} from "forge-std/src/Test.sol";
import {DeployRouter} from "script/Router/01_DeployRouter.s.sol";
import {Router} from "src/Router.sol";

contract Router__DeployRouterScript is Test, DeployRouter {
    function test_RouterIsCorrectlyDeployed() external {
        // it sets the sender as owner

        Router router = _run();

        assertEq(router.owner(), DAO.GOVERNANCE);
    }
}
