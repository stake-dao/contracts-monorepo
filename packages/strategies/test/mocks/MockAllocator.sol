// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IAllocator} from "src/interfaces/IAllocator.sol";

contract MockAllocator is IAllocator {
    function getDepositAllocation(address asset, uint256 amount) external view returns (Allocation memory) {
        return Allocation({gauge: address(0), targets: new address[](0), amounts: new uint256[](0)});
    }

    function getWithdrawAllocation(address asset, uint256 amount) external view returns (Allocation memory) {
        return Allocation({gauge: address(0), targets: new address[](0), amounts: new uint256[](0)});
    }
}
