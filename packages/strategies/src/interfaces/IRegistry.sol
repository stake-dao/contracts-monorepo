/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IRegistry {
    function vaults(address) external view returns (address);

    function allowed(address, bytes4 selector) external view returns (bool);

    function STRATEGY() external view returns (address);
    function ALLOCATOR() external view returns (address);
    function HARVESTER() external view returns (address);
}
