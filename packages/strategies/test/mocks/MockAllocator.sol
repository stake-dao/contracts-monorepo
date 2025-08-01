// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IAllocator} from "src/interfaces/IAllocator.sol";

contract MockAllocator is IAllocator {
    function getDepositAllocation(address asset, address, uint256 amount) external view returns (Allocation memory) {
        address[] memory targets = new address[](1);
        targets[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        return Allocation({asset: address(asset), gauge: address(asset), targets: targets, amounts: amounts});
    }

    function getWithdrawalAllocation(address asset, address, uint256 amount)
        external
        view
        returns (Allocation memory)
    {
        address[] memory targets = new address[](1);
        targets[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        return Allocation({asset: address(asset), gauge: address(asset), targets: targets, amounts: amounts});
    }

    function getRebalancedAllocation(address asset, address, uint256 amount)
        external
        view
        returns (Allocation memory)
    {
        address[] memory targets = new address[](1);
        targets[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        return Allocation({asset: address(asset), gauge: address(asset), targets: targets, amounts: amounts});
    }

    function getAllocationTargets(address) external view returns (address[] memory) {
        address[] memory targets = new address[](1);
        targets[0] = msg.sender;

        return targets;
    }
}
