// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

contract MockLocker {
    function execute(address target, uint256 value, bytes calldata data) external returns (bool success) {
        (success,) = target.call{value: value}(data);
    }
}
