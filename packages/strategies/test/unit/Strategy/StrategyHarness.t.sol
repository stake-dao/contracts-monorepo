// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/mocks/ITokenMinter.sol";
import {Test} from "forge-std/src/Test.sol";

import "src/Strategy.sol";

// Exposes the useful internal functions of the Strategy contract for testing purposes
contract StrategyHarness is Strategy, Test {
    using TransientSlot for *;

    bytes32 private constant FLUSH_AMOUNT_SLOT = keccak256("strategy.flush.amount");

    // Storage for cheat values
    uint256 private _mockHarvestAmount;
    IStrategy.PendingRewards private _mockSyncRewards;

    constructor(address _registry, bytes4 _protocolId, address _locker, address _gateway)
        Strategy(_registry, _protocolId, _locker, _gateway)
    {}

    // Expose transient storage access
    function exposed_getFlushAmount() external view returns (uint256) {
        return FLUSH_AMOUNT_SLOT.asUint256().tload();
    }

    function _cheat_setFlushAmount(uint256 amount) external {
        FLUSH_AMOUNT_SLOT.asUint256().tstore(amount);
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

    function _harvest(address, bytes calldata) internal view override returns (uint256) {
        return _mockHarvestAmount;
    }

    function _deposit(address target, uint256 amount) internal view override {
        require(IERC20(target).balanceOf(address(LOCKER)) >= amount, DepositFailed());
    }

    function _withdraw(address target, uint256 amount, address receiver) internal override {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", receiver, amount);
        require(_executeTransaction(target, data), WithdrawFailed());
    }
}
