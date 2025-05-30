// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface ICakeV3 {
    struct DelegatorConfig {
        address VECakeUser;
        address delegator;
    }

    function getUserCreditWithIfoAddr(address _user, address _ifo) external view returns (uint256);
    function getUserCredit(address _user) external view returns (uint256);
    function approveToVECakeUser(address _user) external;
    function setDelegators(DelegatorConfig[] calldata _delegators) external;
    function delegated(address _user) external view returns (address);
    function delegatorApprove(address _user) external view returns (address);
    function getVeCakeUser(address _user) external view returns (address);
}
