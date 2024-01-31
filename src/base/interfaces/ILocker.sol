// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface ILocker {
    function acceptGovernance() external;

    function claimRewards(address _rewardToken, address _recipient) external;

    function execute(address _to, uint256 _value, bytes calldata _data) external returns (bool, bytes memory);

    function increaseAmount(uint256 _amount) external;

    function increaseUnlockTime(uint256 _time) external;

    function release() external;

    function release(address _recipient) external;

    function setGovernance(address _gov) external;

    function setStrategy(address _strategy) external;

    function transferGovernance(address _governance) external;

    function governance() external view returns (address);
}
