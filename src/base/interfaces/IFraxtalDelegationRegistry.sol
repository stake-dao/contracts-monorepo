// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface IFraxtalDelegationRegistry {
    function delegationsOf(address _delegator) external view returns (address);

    function delegationManagementDisabled(address _addr) external view returns (bool);

    function selfManagingDelegations(address _addr) external view returns (bool);
}
