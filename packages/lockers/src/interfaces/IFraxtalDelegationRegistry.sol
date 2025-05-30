// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IFraxtalDelegationRegistry {
    function delegationsOf(address _delegator) external view returns (address);

    function delegationManagementDisabled(address _addr) external view returns (bool);

    function selfManagingDelegations(address _addr) external view returns (bool);
}
