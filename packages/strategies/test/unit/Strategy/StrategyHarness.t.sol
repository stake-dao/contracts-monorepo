// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import "src/Strategy.sol";
import "test/mocks/ITokenMinter.sol";

// Exposes the useful internal functions of the Strategy contract for testing purposes
contract StrategyHarness is Strategy, Test {
    using TransientSlot for *;

    // Storage for cheat values
    uint256 private _mockHarvestAmount;
    uint256 private _mockFlushAmount;

    IStrategy.PendingRewards private _mockSyncRewards;

    constructor(address _registry, bytes4 _protocolId, address _locker, address _gateway)
        Strategy(_registry, _protocolId, _locker, _gateway)
    {}

    function _getFlushAmount() internal view override returns (uint256) {
        return _mockFlushAmount;
    }

    function _setFlushAmount(uint256 amount) internal override {
        _mockFlushAmount = amount;
    }

    // Expose transient storage access
    function exposed_getFlushAmount() external view returns (uint256) {
        return _getFlushAmount();
    }

    function _cheat_setFlushAmount(uint256 amount) external {
        _setFlushAmount(amount);
    }

    // Cheat functions to set mock return values
    function _cheat_setLockerHarvestAmount(uint256 amount) external {
        _mockHarvestAmount = amount;
        ITokenMinter(address(REWARD_TOKEN)).mint(LOCKER, amount);
    }

    function _cheat_setSyncRewards(uint128 feeSubjectAmount, uint128 totalAmount) external {
        _mockSyncRewards.feeSubjectAmount = feeSubjectAmount;
        _mockSyncRewards.totalAmount = totalAmount;
    }

    function _cheat_setAllocationTargets(address gauge, address allocator, address[] memory targets) external {
        vm.mockCall(
            address(allocator),
            abi.encodeWithSelector(IAllocator.getAllocationTargets.selector, gauge),
            abi.encode(targets)
        );
    }

    function _cheat_getRebalancedAllocation(
        address gauge,
        address allocator,
        uint256 amount,
        IAllocator.Allocation memory allocation
    ) external {
        vm.mockCall(
            address(allocator),
            abi.encodeWithSelector(IAllocator.getRebalancedAllocation.selector, gauge, amount),
            abi.encode(allocation)
        );
    }

    function _cheat_setSidecarBalance(address sidecar, uint256 balance) external {
        vm.mockCall(address(sidecar), abi.encodeWithSelector(ISidecar.balanceOf.selector), abi.encode(balance));
    }

    function _sync(address) internal view override returns (IStrategy.PendingRewards memory) {
        return _mockSyncRewards;
    }

    function _harvestLocker(address, bytes memory) internal view override returns (uint256) {
        return _mockHarvestAmount;
    }

    function _deposit(address target, uint256 amount) internal view override {
        require(IERC20(target).balanceOf(address(LOCKER)) >= amount, DepositFailed());
    }

    function _withdraw(address, address target, uint256 amount, address receiver) internal override {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", receiver, amount);
        require(_executeTransaction(target, data), WithdrawFailed());
    }
}
