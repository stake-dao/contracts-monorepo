// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface ICakeLocker {
    function claimRevenue(address[] memory revenueSharingPools) external;
    function setRevenueSharingPoolGateway(address rspg) external;
    function rspg() external view returns (address);
    function transferGovernance(address governance) external;
}
