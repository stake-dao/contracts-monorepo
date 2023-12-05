// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IRevenueSharingPoolGateway {
    function claimMultipleWithoutProxy(address[] calldata _revenueSharingPools, address _for) external;
}
