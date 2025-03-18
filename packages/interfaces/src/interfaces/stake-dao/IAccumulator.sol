// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface IAccumulator {
    function depositTokenWithoutChargingFee(address _token, uint256 _amount) external;
}
