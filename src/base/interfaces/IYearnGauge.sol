// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IYearnGauge {
    function getReward(address _account) external;

    function setRecipient(address _recipient) external;
}
