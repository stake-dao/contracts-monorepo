// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IYearnRegistry {
    function registered(address _gauge) external view returns (bool);
}
