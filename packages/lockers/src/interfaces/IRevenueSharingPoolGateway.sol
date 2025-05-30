// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IRevenueSharingPoolGateway {
    function claimMultipleWithoutProxy(address[] calldata _revenueSharingPools, address _for) external;
}
