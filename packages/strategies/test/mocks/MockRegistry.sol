// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {console} from "forge-std/src/console.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";

contract MockRegistry is IRegistry {
    address public vault;
    bool public isAllowed;
    address public strategy;
    address public allocator;
    address public harvester;
    address public feeReceiver;
    address public accountant;

    function vaults(address) external view returns (address) {
        return vault;
    }

    function assets(address) external pure returns (address) {
        return address(0);
    }

    function allowed(address, address, bytes4) external view returns (bool) {
        return isAllowed;
    }

    function setAllowed(bool _isAllowed) external {
        isAllowed = _isAllowed;
    }

    function setFeeReceiver(address _feeReceiver) external {
        feeReceiver = _feeReceiver;
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

    function setAccountant(address _accountant) external {
        accountant = _accountant;
    }
}
