// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IExecutor {
    function allowAddress(address _address) external;

    function execute(address _to, uint256 _value, bytes calldata _data) external returns (bool, bytes memory);

    function callExecuteTo(address _executor, address _to, uint256 _value, bytes calldata _data)
        external
        returns (bool, bytes memory);
}
