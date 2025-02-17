/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IRegistry {
    function vaults(address) external view returns (address);
    function assets(address) external view returns (address);

    function allowed(address, bytes4 selector) external view returns (bool);

    function strategy() external view returns (address);
    function allocator() external view returns (address);
    function HARVESTER() external view returns (address);
    function FEE_RECEIVER() external view returns (address);
    function accountant() external view returns (address);
}
