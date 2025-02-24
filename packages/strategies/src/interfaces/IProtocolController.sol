/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IProtocolController {
    function vaults(address) external view returns (address);
    function assets(address) external view returns (address);

    function allowed(address, address, bytes4 selector) external view returns (bool);

    function strategy(bytes4 protocolId) external view returns (address);
    function allocator(bytes4 protocolId) external view returns (address);
    function harvester(bytes4 protocolId) external view returns (address);
    function accountant(bytes4 protocolId) external view returns (address);
    function feeReceiver(bytes4 protocolId) external view returns (address);
}
