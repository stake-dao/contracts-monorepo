// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAllocator} from "src/interfaces/IAllocator.sol";

/// @title Allocator
/// @author Stake DAO
/// @notice Determines where to deploy capital for optimal yield
/// @dev Base implementation sends everything to locker. Protocol-specific allocators
///      (e.g., OnlyBoostAllocator) override to split between locker and sidecars
///      based on yield optimization strategies
contract Allocator is IAllocator {
    /// @notice The locker that holds and stakes protocol tokens (e.g., veCRV holder)
    address public immutable LOCKER;

    /// @notice Safe multisig that executes transactions (same as locker on L2s)
    address public immutable GATEWAY;

    /// @notice Error thrown when the gateway is zero address
    error GatewayZeroAddress();

    /// @notice Initializes the allocator with locker and gateway addresses
    /// @param _locker Protocol's token holder (pass 0 for L2s where gateway holds tokens)
    /// @param _gateway Safe multisig that executes transactions
    constructor(address _locker, address _gateway) {
        require(_gateway != address(0), GatewayZeroAddress());

        GATEWAY = _gateway;
        // L2 optimization: gateway acts as both executor and token holder
        LOCKER = _locker == address(0) ? _gateway : _locker;
    }

    /// @notice Calculates where to send deposited LP tokens
    /// @dev Base: 100% to locker. Override for complex strategies (e.g., split with Convex)
    /// @param asset LP token being deposited
    /// @param gauge Target gauge for staking
    /// @param amount Total amount to allocate
    /// @return Allocation with single target (locker) and full amount
    function getDepositAllocation(address asset, address gauge, uint256 amount)
        public
        view
        virtual
        returns (Allocation memory)
    {
        address[] memory targets = new address[](1);
        targets[0] = LOCKER;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        return Allocation({asset: asset, gauge: gauge, targets: targets, amounts: amounts});
    }

    /// @notice Calculates where to pull LP tokens from during withdrawal
    /// @dev Base: 100% from locker. Override to handle multiple sources
    /// @param asset LP token being withdrawn
    /// @param gauge Source gauge
    /// @param amount Total amount to withdraw
    /// @return Allocation with single source (locker) and full amount
    function getWithdrawalAllocation(address asset, address gauge, uint256 amount)
        public
        view
        virtual
        returns (Allocation memory)
    {
        address[] memory targets = new address[](1);
        targets[0] = LOCKER;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        return Allocation({asset: asset, gauge: gauge, targets: targets, amounts: amounts});
    }

    /// @notice Calculates optimal distribution when rebalancing positions
    /// @dev Base: same as deposit. Override to implement rebalancing logic
    /// @param asset LP token to rebalance
    /// @param gauge Target gauge
    /// @param amount Total amount to redistribute
    /// @return Allocation with rebalancing targets and amounts
    function getRebalancedAllocation(address asset, address gauge, uint256 amount)
        public
        view
        virtual
        returns (Allocation memory)
    {
        return getDepositAllocation(asset, gauge, amount);
    }

    /// @notice Lists all possible allocation targets for a gauge
    /// @dev Base: only locker. Override to include sidecars
    /// @return targets Array of addresses that can receive allocations
    function getAllocationTargets(address /*gauge*/ ) public view virtual returns (address[] memory) {
        address[] memory targets = new address[](1);
        targets[0] = LOCKER;

        return targets;
    }
}
