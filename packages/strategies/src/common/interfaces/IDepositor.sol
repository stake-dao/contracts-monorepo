// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IDepositor {
    function FEE_DENOMINATOR() external view returns (uint256);

    function gauge() external view returns (address);

    function incentiveToken() external view returns (uint256);

    function lockIncentive() external view returns (uint256);
}
