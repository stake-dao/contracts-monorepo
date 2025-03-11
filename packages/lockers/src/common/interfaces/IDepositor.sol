// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

interface IDepositor {
    error ADDRESS_ZERO();
    error AMOUNT_ZERO();

    function zeroLockedTokenId() external returns (uint256 zeroLockedTokenId);

    function deposit(uint256 amount, bool lock, bool stake, address user) external;

    function setSdTokenOperator(address newOperator) external;

    function transferGovernance(address _governance) external;
}
