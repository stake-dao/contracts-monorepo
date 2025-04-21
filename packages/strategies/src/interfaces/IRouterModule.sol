// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IRouterModule {
    function name() external view returns (string memory name);
    function version() external view returns (string memory version);
}
