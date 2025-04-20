// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {RouterBaseTest} from "./RouterBaseTest.t.sol";

contract Router__getters is RouterBaseTest {
    function test_ReturnsTheVersion() external view {
        // it returns the version
        assertEq(router.version(), "1.0.0");
    }

    function test_ReturnsTheBuffer() external view {
        // it returns the buffer
        assertEq(router.getStorageBuffer(), keccak256("STAKEDAO.STAKING.V2.ROUTER.V1"));
    }

    function test_ReturnsTheOwner() external view {
        // it returns the owner
        assertEq(router.owner(), owner);
    }
}
