// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IYearnRewardPool {
    // solhint-disable-next-line
    function checkpoint_token() external;

    // solhint-disable-next-line
    function checkpoint_total_supply() external;

    function claim(address _user) external;
}
