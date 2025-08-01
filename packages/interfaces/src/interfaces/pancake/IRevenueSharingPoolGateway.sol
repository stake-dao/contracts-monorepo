// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IRevenueSharingPoolGateway {
    function claimMultiple(address[] calldata _revenueSharingPools, address _for) external;
    function claimMultipleWithoutProxy(address[] calldata _revenueSharingPools, address _for) external;
}
