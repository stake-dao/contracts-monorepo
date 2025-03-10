pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Strategy, IStrategy} from "src/Strategy.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";

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

    function exposed_setFlushAmount(uint256 amount) external {
        FLUSH_AMOUNT_SLOT.asUint256().tstore(amount);
    }

    // Cheat functions to set mock return values
    function _cheat_setHarvestAmount(uint256 amount) external {
        _mockHarvestAmount = amount;
    }

    function _cheat_setSyncRewards(uint128 feeSubjectAmount, uint128 totalAmount) external {
        _mockSyncRewards.feeSubjectAmount = feeSubjectAmount;
        _mockSyncRewards.totalAmount = totalAmount;
    }

    function _sync(address) internal view override returns (IStrategy.PendingRewards memory) {
        return _mockSyncRewards;
    }

    function _harvest(address, bytes calldata) internal view override returns (uint256) {
        return _mockHarvestAmount;
    }

    function _deposit(address, uint256) internal override {}

    function _withdraw(address, uint256, address) internal override {}
}
