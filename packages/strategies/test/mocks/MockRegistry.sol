// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IRegistry} from "src/interfaces/IRegistry.sol";

contract MockRegistry is IRegistry {
    address public vault;
    address public strategy;
    address public allocator;
    address public harvester;

    function vaults(address) external view returns (address) {
        return vault;
    }

    function ALLOCATOR() external view returns (address) {
        return allocator;
    }

    function STRATEGY() external view returns (address) {
        return strategy;
    }

    function HARVESTER() external view returns (address) {
        return harvester;
    }

    function allowed(address, bytes4) external pure returns (bool) {
        return true;
    }

    function setVault(address _vault) external {
        vault = _vault;
    }

    function setStrategy(address _strategy) external {
        strategy = _strategy;
    }

    function setAllocator(address _allocator) external {
        allocator = _allocator;
    }

    function setHarvester(address _harvester) external {
        harvester = _harvester;
    }
}
