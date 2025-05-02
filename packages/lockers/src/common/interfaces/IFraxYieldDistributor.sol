// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

interface IFraxYieldDistributor {
    function getYield() external returns (uint256);
}
