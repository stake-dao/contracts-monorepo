// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IRouterModule {
    function name() external view returns (string memory name);
    function version() external view returns (string memory version);
}
