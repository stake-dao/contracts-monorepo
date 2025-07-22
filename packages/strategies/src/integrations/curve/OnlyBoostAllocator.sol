// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CurveProtocol} from "@address-book/src/CurveEthereum.sol";
import {Allocator} from "src/Allocator.sol";
import {IBalanceProvider} from "src/interfaces/IBalanceProvider.sol";
import {ISidecar} from "src/interfaces/ISidecar.sol";
import {ISidecarFactory} from "src/interfaces/ISidecarFactory.sol";

/// @title OnlyBoostAllocator.
/// @author Stake DAO
/// @custom:github @stake-dao
/// @custom:contact contact@stakedao.org

/// @notice Calculates the optimal LP token allocation for Stake DAO Locker and Convex.
contract OnlyBoostAllocator is Allocator {
    using Math for uint256;

    /// @notice Address of the Curve Boost Delegation V3 contract
    address public immutable BOOST_PROVIDER;

    /// @notice Address of the Convex Boost Holder contract
    address public immutable CONVEX_BOOST_HOLDER;

    /// @notice Address of the Convex Sidecar Factory contract
    ISidecarFactory public immutable CONVEX_SIDECAR_FACTORY;

    /// @notice Initializes the OnlyBoostAllocator contract
    /// @param _locker Address of the Stake DAO Liquidity Locker
    /// @param _gateway Address of the gateway contract
    /// @param _convexSidecarFactory Address of the Convex Sidecar Factory contract
    constructor(
        address _locker,
        address _gateway,
        address _convexSidecarFactory,
        address _boostProvider,
        address _convexBoostHolder
    ) Allocator(_locker, _gateway) {
        BOOST_PROVIDER = _boostProvider;
        CONVEX_BOOST_HOLDER = _convexBoostHolder;
        CONVEX_SIDECAR_FACTORY = ISidecarFactory(_convexSidecarFactory);
    }

    //////////////////////////////////////////////////////
    // --- DEPOSIT ALLOCATION
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

        // 5. Get the optimal balance based on Convex balance and veBoost ratio.
        uint256 optimalBalanceOfLocker = getOptimalLockerBalance(gauge);

        // 6. Calculate the amount of lps to deposit into the locker.
        alloc.amounts[1] =
            optimalBalanceOfLocker > balanceOfLocker ? Math.min(optimalBalanceOfLocker - balanceOfLocker, amount) : 0;

        // 7. Calculate the amount of lps to deposit into the sidecar.
        alloc.amounts[0] = amount - alloc.amounts[1];
    }

    //////////////////////////////////////////////////////
    // --- WITHDRAWAL ALLOCATION
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
        uint256 balanceOfSidecar = ISidecar(sidecar).balanceOf();
        uint256 balanceOfLocker = IBalanceProvider(gauge).balanceOf(LOCKER);

        // 5. Calculate the optimal amount of lps that must be held by the locker.
        uint256 optimalBalanceOfLocker = getOptimalLockerBalance(gauge);

        // 6. Calculate the total balance.
        uint256 totalBalance = balanceOfSidecar + balanceOfLocker;

        // 7. Adjust the withdrawal based on the optimal amount for Stake DAO
        if (totalBalance <= amount) {
            // 7a. If the total balance is less than or equal to the withdrawal amount, withdraw everything
            alloc.amounts[0] = balanceOfSidecar;
            alloc.amounts[1] = balanceOfLocker;
        } else if (optimalBalanceOfLocker >= balanceOfLocker) {
            // 7b. If Stake DAO balance is below optimal, prioritize withdrawing from Convex
            alloc.amounts[0] = Math.min(amount, balanceOfSidecar);
            alloc.amounts[1] = amount > alloc.amounts[0] ? amount - alloc.amounts[0] : 0;
        } else {
            // 7c. If Stake DAO is above optimal, prioritize withdrawing from Stake DAO,
            //     but only withdraw as much as needed to bring the balance down to the optimal amount.
            alloc.amounts[1] = Math.min(amount, balanceOfLocker - optimalBalanceOfLocker);
            alloc.amounts[0] = amount > alloc.amounts[1] ? Math.min(amount - alloc.amounts[1], balanceOfSidecar) : 0;

            // 7d. If there is still more to withdraw, withdraw the rest from Stake DAO.
            if (amount > alloc.amounts[0] + alloc.amounts[1]) {
                alloc.amounts[1] += amount - alloc.amounts[0] - alloc.amounts[1];
            }
        }
    }

    //////////////////////////////////////////////////////
    // --- REBALANCE ALLOCATION
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

        // 3. For rebalancing, we still want to match the optimal balance based on Convex holdings
        // This ensures we maintain the boost-maximizing ratio
        uint256 optimalLockerBalance = getOptimalLockerBalance(gauge);

        // Cap the locker amount to the total balance available
        alloc.amounts[1] = Math.min(optimalLockerBalance, totalBalance);
        alloc.amounts[0] = totalBalance - alloc.amounts[1];
    }

    //////////////////////////////////////////////////////
    // --- VIEW HELPER FUNCTIONS
    //////////////////////////////////////////////////////

    /// @inheritdoc Allocator
    function getAllocationTargets(address gauge) public view override returns (address[] memory) {
        address sidecar = CONVEX_SIDECAR_FACTORY.sidecar(gauge);
        return sidecar == address(0) ? super.getAllocationTargets(gauge) : _targets(sidecar);
    }

    /// @notice Returns the optimal amount of LP token that must be held by Stake DAO Locker
    /// @dev Calculates the optimal balance to maximize boost efficiency
    /// @param gauge Address of the Curve gauge
    /// @return balanceOfLocker Optimal amount of LP token that should be held by Stake DAO Locker
    function getOptimalLockerBalance(address gauge) public view returns (uint256 balanceOfLocker) {
        // 1. Get the balance of veBoost on Stake DAO and Convex
        uint256 veBoostOfLocker = IBalanceProvider(BOOST_PROVIDER).balanceOf(LOCKER);
        uint256 veBoostOfConvex = IBalanceProvider(BOOST_PROVIDER).balanceOf(CONVEX_BOOST_HOLDER);

        // 2. Get the balance of the liquidity gauge on Convex
        uint256 balanceOfConvex = IBalanceProvider(gauge).balanceOf(CONVEX_BOOST_HOLDER);

        // 3. If there is no balance of Convex or no veBoost on Convex, return 0
        if (balanceOfConvex == 0 || veBoostOfConvex == 0) return 0;

        // 4. Compute the optimal balance for Stake DAO based on veBoost ratio
        // This ensures Stake DAO gets LP tokens proportional to its veBoost advantage
        balanceOfLocker = balanceOfConvex.mulDiv(veBoostOfLocker, veBoostOfConvex);
    }

    //////////////////////////////////////////////////////
    // --- HELPER FUNCTIONS
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
}
