// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IExecutor {
    function execute(address _to, uint256 _value, bytes calldata _data) external returns (bool, bytes memory);
}
