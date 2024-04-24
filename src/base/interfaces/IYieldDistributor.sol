// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IYieldDistributor {
    function getYield() external returns (uint256);

    function checkpoint() external;

    function userVeFXSCheckpointed(address _user) external view returns (uint256);
}
