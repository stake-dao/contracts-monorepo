// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IRouter {
    function execute(bytes[] calldata data) external payable returns (bytes[] memory returnData);
    function setModule(uint8 identifier, address module) external;
    function safeSetModule(uint8 identifier, address module) external;
    function getModule(uint8 identifier) external view returns (address module);
    function getModuleName(uint8 identifier) external view returns (string memory name);
    function version() external view returns (string memory version);
}
