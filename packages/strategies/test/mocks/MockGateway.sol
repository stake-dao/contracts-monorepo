// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface SimpleModuleManager {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        IModuleManager.Operation operation
    ) external returns (bool success);
}

contract MockGateway is SimpleModuleManager {
    address internal locker;

    constructor(address _locker) {
        locker = _locker;
    }

    function execTransactionFromModule(address, uint256 value, bytes calldata data, IModuleManager.Operation)
        external
        override
        returns (bool success)
    {
        (success,) = locker.call{value: value}(data);
    }
}
