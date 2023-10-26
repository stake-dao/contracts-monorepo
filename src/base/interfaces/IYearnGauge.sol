// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IYearnGauge {
    function getReward() external;

    function setRecipient(address _recipient) external;
}
