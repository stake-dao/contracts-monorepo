// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ILocker {
    function execute(address _to, uint256 _value, bytes calldata _data) external returns (bool, bytes memory);

    function increaseAmount(uint256 _amount) external;

    function release() external;

    function setGovernance(address _gov) external;

    function setStrategy(address _strategy) external;
}
