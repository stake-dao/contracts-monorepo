// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface ICakeV3 {
    function getUserCreditWithIfoAddr(address _user, address _ifo) external view returns (uint256);
    function getUserCredit(address _user) external view returns (uint256);
}
