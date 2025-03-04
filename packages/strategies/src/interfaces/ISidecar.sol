/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface ISidecar {
    function balanceOf() external view returns (uint256);
    function withdraw(uint256 amount, address receiver) external;
    function withdrawAll(address receiver) external;
    function deposit(uint256 amount) external;
    function earned() external view returns (uint256);
}
