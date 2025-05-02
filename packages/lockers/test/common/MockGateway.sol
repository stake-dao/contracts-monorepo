// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";

interface SimpleModuleManager {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        IModuleManager.Operation operation
    ) external returns (bool success);

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        IModuleManager.Operation operation
    ) external returns (bool success, bytes memory returnData);
}

contract MockGateway is SimpleModuleManager {
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        IModuleManager.Operation
    ) external override returns (bool success, bytes memory returnData) {
        (success, returnData) = to.call{value: value}(data);
        return (success, returnData);
    }

    function execTransactionFromModule(address to, uint256 value, bytes calldata data, IModuleManager.Operation)
        external
        override
        returns (bool success)
    {
        (success,) = to.call{value: value}(data);
    }
}
