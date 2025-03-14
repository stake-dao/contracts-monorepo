// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {console} from "forge-std/src/console.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

contract MockRegistry is IProtocolController {
    bool private _isAllowed;
    address private _vault;
    address private _strategy;
    address private _allocator;
    address private _harvester;
    address private _feeReceiver;
    address private _accountant;
    address private _rewardReceiver;

    bool private _permissionSetter;

    function permissionSetters(address) external view returns (bool) {
        return _permissionSetter;
    }

    function setPermissionSetter(address, bool) external {}

    function setPermission(address, address, bytes4, bool) external {}

    function registerVault(address, address, address, address, bytes4) external {}

    function setRewardReceiver(address rewardReceiver_) external {
        _rewardReceiver = rewardReceiver_;
    }

    function isRegistrar(address) external view returns (bool) {
        return true;
    }

    function shutdown(address) external {}

    function isShutdown(address) external pure returns (bool) {
        return false;
    }

    function vaults(address) external view returns (address) {
        return _vault;
    }

    function strategy(bytes4) external view override returns (address) {
        return _strategy;
    }

    function allocator(bytes4) external view override returns (address) {
        return _allocator;
    }

    function accountant(bytes4) external view override returns (address) {
        return _accountant;
    }

    function feeReceiver(bytes4) external view override returns (address) {
        return _feeReceiver;
    }

    function asset(address) external pure override returns (address) {
        return address(0);
    }

    function allowed(address, address, bytes4) external view returns (bool) {
        return _isAllowed;
    }

    function rewardReceiver(address) external view override returns (address) {
        return _rewardReceiver;
    }

    function setAllowed(bool isAllowed_) external {
        _isAllowed = isAllowed_;
    }

    function setFeeReceiver(address feeReceiver_) external {
        _feeReceiver = feeReceiver_;
    }

    function setVault(address vault_) external {
        _vault = vault_;
    }

    function setStrategy(address strategy_) external {
        _strategy = strategy_;
    }

    function setAllocator(address allocator_) external {
        _allocator = allocator_;
    }

    function setHarvester(address harvester_) external {
        _harvester = harvester_;
    }

    function setAccountant(address accountant_) external {
        _accountant = accountant_;
    }
}
