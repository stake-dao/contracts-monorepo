// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IHarvester {
    function harvest(address asset, bytes calldata extraData)
        external
        returns (uint256 feeSubjectAmount, uint256 totalAmount);
}
