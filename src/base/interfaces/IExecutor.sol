// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IExecutor {
    function allowAddress(address _addr) external;

    function callExecuteTo(address _executor, address _to, uint256 _value, bytes calldata _data)
        external
        returns (bool success_, bytes memory result_);

    function execute(address _to, uint256 _value, bytes calldata _data)
        external
        returns (bool success_, bytes memory result_);
}
