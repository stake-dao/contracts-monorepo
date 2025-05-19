// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IExecutor {
    function allowAddress(address _address) external;

    function execute(address _to, uint256 _value, bytes calldata _data) external returns (bool, bytes memory);

    function callExecuteTo(address _executor, address _to, uint256 _value, bytes calldata _data)
        external
        returns (bool, bytes memory);
}
