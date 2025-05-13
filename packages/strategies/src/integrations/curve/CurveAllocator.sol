// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Allocator} from "src/Allocator.sol";
import {ISidecar} from "src/interfaces/ISidecar.sol";
import {ISidecarFactory} from "src/interfaces/ISidecarFactory.sol";
import {IBalanceProvider} from "src/interfaces/IBalanceProvider.sol";

/// @title CurveAllocator
/// @notice Contract that calculates the optimal LP token allocation for Stake DAO Locker and Convex
contract CurveAllocator is Allocator {
    using Math for uint256;

    /// @notice Address of the Convex Sidecar Factory contract
    ISidecarFactory public immutable CONVEX_SIDECAR_FACTORY;

    /// @notice Address of the Curve Boost Delegation V3 contract
    address public constant BOOST_DELEGATION_V3 = 0xD37A6aa3d8460Bd2b6536d608103D880695A23CD;

    /// @notice Address of the Convex Boost Holder contract
    address public constant CONVEX_BOOST_HOLDER = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    /// @notice Initializes the CurveAllocator contract
    /// @param _locker Address of the Stake DAO Liquidity Locker
    /// @param _gateway Address of the gateway contract
    /// @param _convexSidecarFactory Address of the Convex Sidecar Factory contract
    constructor(address _locker, address _gateway, address _convexSidecarFactory) Allocator(_locker, _gateway) {
        CONVEX_SIDECAR_FACTORY = ISidecarFactory(_convexSidecarFactory);
    }

    //////////////////////////////////////////////////////
    /// --- DEPOSIT ALLOCATION
    //////////////////////////////////////////////////////

    /// @inheritdoc Allocator
    function getDepositAllocation(address asset, address gauge, uint256 amount)
        public
        view
        override
        returns (Allocation memory alloc)
    {
        // 1. Resolve the sidecar for the gauge.
        address sidecar = CONVEX_SIDECAR_FACTORY.sidecar(gauge);

        // 2. If no sidecar exists, delegate to the base allocator.
        if (sidecar == address(0)) {
            return super.getDepositAllocation(asset, gauge, amount);
        }

        // 3. Prepare targets and amounts containers.
        alloc.asset = asset;
        alloc.gauge = gauge;
        alloc.targets = _targets(sidecar);
        alloc.amounts = _pair(0, 0);

        // 4. Fetch current balances.
        uint256 balanceOfLocker = IBalanceProvider(gauge).balanceOf(LOCKER);
        uint256 balanceOfSidecar = ISidecar(sidecar).balanceOf();
        uint256 total = balanceOfLocker + balanceOfSidecar + amount;

        // 5. Compute the optimal Locker balance after the deposit.
        uint256 optimalLocker = _computeLockerAllocation(total);

        // 6. Determine how much to send to the Locker.
        uint256 toLocker = optimalLocker > balanceOfLocker ? optimalLocker - balanceOfLocker : 0;
        if (toLocker > amount) toLocker = amount; // Cap to available amount

        // 7. Assign amounts.
        alloc.amounts[1] = toLocker; // to Locker
        alloc.amounts[0] = amount - toLocker; // remainder to Sidecar
    }

    //////////////////////////////////////////////////////
    /// --- WITHDRAWAL ALLOCATION
    //////////////////////////////////////////////////////

    /// @inheritdoc Allocator
    function getWithdrawalAllocation(address asset, address gauge, uint256 amount)
        public
        view
        override
        returns (Allocation memory alloc)
    {
        // 1. Resolve the sidecar.
        address sidecar = CONVEX_SIDECAR_FACTORY.sidecar(gauge);

        // 2. Fallback to base allocator if none.
        if (sidecar == address(0)) {
            return super.getWithdrawalAllocation(asset, gauge, amount);
        }

        // 3. Prepare return struct.
        alloc.asset = asset;
        alloc.gauge = gauge;
        alloc.targets = _targets(sidecar);
        alloc.amounts = _pair(0, 0);

        // 4. Current balances.
        uint256 balanceOfLocker = IBalanceProvider(gauge).balanceOf(LOCKER);
        uint256 balanceOfSidecar = ISidecar(sidecar).balanceOf();
        uint256 totalBalance = balanceOfLocker + balanceOfSidecar;

        // 5. If requesting the whole balance, withdraw everything.
        if (amount >= totalBalance) {
            alloc.amounts[0] = balanceOfSidecar;
            alloc.amounts[1] = balanceOfLocker;
            return alloc;
        }

        // 6. Compute optimal post‑withdraw Locker target.
        uint256 total = totalBalance - amount;

        uint256 lockerTarget = _computeLockerAllocation(total);

        // 7. Withdraw up to the Locker’s excess first.
        uint256 excessLocker = balanceOfLocker > lockerTarget ? balanceOfLocker - lockerTarget : 0;
        uint256 fromLocker = Math.min(amount, excessLocker);

        // 8. Withdraw any remaining amount from the Side‑car.
        uint256 fromSidecar = amount - fromLocker;
        if (fromSidecar > balanceOfSidecar) fromSidecar = balanceOfSidecar;

        // 9. If we’re still short, take the rest from the Locker (may dip below target).
        uint256 shortfall = amount - (fromLocker + fromSidecar);
        if (shortfall > 0) {
            uint256 extraFromLocker = Math.min(shortfall, balanceOfLocker - fromLocker);
            fromLocker += extraFromLocker;
        }

        // 10. Assign amounts.
        alloc.amounts[0] = fromSidecar;
        alloc.amounts[1] = fromLocker;
    }

    //////////////////////////////////////////////////////
    /// --- REBALANCE ALLOCATION
    //////////////////////////////////////////////////////

    /// @inheritdoc Allocator
    function getRebalancedAllocation(address asset, address gauge, uint256 totalBalance)
        public
        view
        override
        returns (Allocation memory alloc)
    {
        // 1. Resolve sidecar.
        address sidecar = CONVEX_SIDECAR_FACTORY.sidecar(gauge);
        if (sidecar == address(0)) {
            return super.getRebalancedAllocation(asset, gauge, totalBalance);
        }

        // 2. Prepare struct.
        alloc.asset = asset;
        alloc.gauge = gauge;
        alloc.targets = _targets(sidecar);
        alloc.amounts = _pair(0, 0);

        // 3. Compute one‑shot optimal split.
        uint256 lockerAmt = _computeLockerAllocation(totalBalance);

        alloc.amounts[1] = lockerAmt;
        alloc.amounts[0] = totalBalance - lockerAmt;
    }

    //////////////////////////////////////////////////////
    /// --- VIEW HELPER FUNCTIONS
    //////////////////////////////////////////////////////

    /// @inheritdoc Allocator
    function getAllocationTargets(address gauge) public view override returns (address[] memory) {
        address sidecar = CONVEX_SIDECAR_FACTORY.sidecar(gauge);
        return sidecar == address(0) ? super.getAllocationTargets(gauge) : _targets(sidecar);
    }

    //////////////////////////////////////////////////////
    /// --- HELPER FUNCTIONS
    //////////////////////////////////////////////////////

    /// @dev Returns the pair `[sidecar, LOCKER]` used by allocation targets.
    function _targets(address sidecar) private view returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = sidecar;
        arr[1] = LOCKER;
    }

    /// @dev Utility to allocate a two‑element uint256 array.
    function _pair(uint256 a0, uint256 a1) private pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a0;
        arr[1] = a1;
    }

    /// @dev Computes the optimal amount to allocate to the locker based on ratio of veBoosts.
    /// @param totalBalance The total balance of the gauge.
    /// @return lockerAmt The optimal amount to allocate to the locker.
    function _computeLockerAllocation(uint256 totalBalance) private view returns (uint256 lockerAmt) {
        uint256 veLocker = IBalanceProvider(BOOST_DELEGATION_V3).balanceOf(LOCKER);
        uint256 veConvex = IBalanceProvider(BOOST_DELEGATION_V3).balanceOf(CONVEX_BOOST_HOLDER);
        lockerAmt = totalBalance.mulDiv(veLocker, veLocker + veConvex);
    }
}
