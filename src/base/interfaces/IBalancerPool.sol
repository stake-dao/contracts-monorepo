// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
}
