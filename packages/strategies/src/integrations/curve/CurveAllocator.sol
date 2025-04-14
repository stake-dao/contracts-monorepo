// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Allocator} from "src/Allocator.sol";
import {IBalanceProvider} from "src/interfaces/IBalanceProvider.sol";
import {ISidecar} from "src/interfaces/ISidecar.sol";
import {ISidecarFactory} from "src/interfaces/ISidecarFactory.sol";

/// @title CurveAllocator
/// @notice Contract that calculates optimal LP token allocation for Stake DAO Locker and Convex
/// @dev Extends the base Allocator contract to provide Curve-specific allocation logic
contract CurveAllocator is Allocator {
    using Math for uint256;

    /// @notice Address of the Curve Boost Delegation V3 contract
    address public constant BOOST_DELEGATION_V3 = 0xD37A6aa3d8460Bd2b6536d608103D880695A23CD;

    /// @notice Address of the Convex Boost Holder contract
    address public constant CONVEX_BOOST_HOLDER = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    /// @notice Address of the Convex Sidecar Factory contract
    ISidecarFactory public immutable CONVEX_SIDECAR_FACTORY;

    /// @notice Initializes the CurveAllocator contract
    /// @param _locker Address of the Stake DAO Liquidity Locker
    /// @param _gateway Address of the gateway contract
    /// @param _convexSidecarFactory Address of the Convex Sidecar Factory contract
    constructor(address _locker, address _gateway, address _convexSidecarFactory) Allocator(_locker, _gateway) {
        CONVEX_SIDECAR_FACTORY = ISidecarFactory(_convexSidecarFactory);
    }

    /// @notice Calculates the optimal allocation for depositing LP tokens
    /// @dev Overrides the base Allocator's getDepositAllocation function to include sidecar logic
    /// @param asset Address of the asset contract
    /// @param gauge Address of the Curve gauge
    /// @param amount Amount of LP tokens to deposit
    /// @return Allocation struct containing targets and amounts for the deposit
    function getDepositAllocation(address asset, address gauge, uint256 amount)
        public
        view
        override
        returns (Allocation memory)
    {
        /// 1. Get the sidecar for the gauge.
        address sidecar = CONVEX_SIDECAR_FACTORY.sidecar(gauge);

        /// 2. If the sidecar is not set, use the default allocation.
        if (sidecar == address(0)) {
            return super.getDepositAllocation(asset, gauge, amount);
        }

        /// 3. Get the targets and amounts for the allocation.
        address[] memory targets = new address[](2);
        targets[0] = sidecar;
        targets[1] = LOCKER;

        uint256[] memory amounts = new uint256[](2);

        /// 4. Get the balance of the locker on the liquidity gauge.
        uint256 balanceOfLocker = IBalanceProvider(gauge).balanceOf(LOCKER);

        /// 5. Get the optimal amount of lps that must be held by the locker.
        uint256 optimalBalanceOfLocker = getOptimalLockerBalance(gauge);

        /// 6. Calculate the amount of lps to deposit into the locker.
        amounts[1] =
            optimalBalanceOfLocker > balanceOfLocker ? Math.min(optimalBalanceOfLocker - balanceOfLocker, amount) : 0;

        /// 7. Calculate the amount of lps to deposit into the sidecar.
        amounts[0] = amount - amounts[1];

        /// 8. Return the allocation.
        return Allocation({asset: asset, gauge: gauge, targets: targets, amounts: amounts});
    }

    /// @notice Calculates the optimal allocation for withdrawing LP tokens
    /// @dev Overrides the base Allocator's getWithdrawalAllocation function to include sidecar logic
    /// @param asset Address of the asset contract
    /// @param gauge Address of the Curve gauge
    /// @param amount Amount of LP tokens to withdraw
    /// @return Allocation struct containing targets and amounts for the withdrawal
    function getWithdrawalAllocation(address asset, address gauge, uint256 amount)
        public
        view
        override
        returns (Allocation memory)
    {
        /// 1. Get the sidecar for the gauge.
        address sidecar = CONVEX_SIDECAR_FACTORY.sidecar(gauge);

        /// 2. If the sidecar is not set, use the default allocation.
        if (sidecar == address(0)) {
            return super.getWithdrawalAllocation(asset, gauge, amount);
        }

        /// 3. Get the targets and amounts for the allocation.
        address[] memory targets = new address[](2);
        targets[0] = sidecar;
        targets[1] = LOCKER;

        uint256[] memory amounts = new uint256[](2);

        /// 4. Get the balance of the sidecar and the locker on the liquidity gauge.
        uint256 balanceOfSidecar = ISidecar(sidecar).balanceOf();
        uint256 balanceOfLocker = IBalanceProvider(gauge).balanceOf(LOCKER);

        /// 5. Calculate the optimal amount of lps that must be held by the locker.
        uint256 optimalBalanceOfLocker = getOptimalLockerBalance(gauge);

        /// 6. Calculate the total balance of the sidecar and the locker.
        uint256 totalBalance = balanceOfSidecar + balanceOfLocker;

        /// 7. Adjust the withdrawal based on the optimal amount for Stake DAO
        if (totalBalance <= amount) {
            /// 7a. If the total balance is less than or equal to the withdrawal amount, withdraw everything
            amounts[0] = balanceOfSidecar;
            amounts[1] = balanceOfLocker;
        } else if (optimalBalanceOfLocker >= balanceOfLocker) {
            /// 7b. If Stake DAO balance is below optimal, prioritize withdrawing from Convex
            amounts[0] = Math.min(amount, balanceOfSidecar);
            amounts[1] = amount > amounts[0] ? amount - amounts[0] : 0;
        } else {
            /// 7c. If Stake DAO balance is above optimal, prioritize withdrawing from Stake DAO
            amounts[1] = Math.min(amount, balanceOfLocker);
            amounts[0] = amount > amounts[1] ? amount - amounts[1] : 0;
        }

        /// 8. Return the allocation.
        return Allocation({asset: asset, gauge: gauge, targets: targets, amounts: amounts});
    }

    /// @notice Returns the targets for the allocation
    /// @dev Overrides the base Allocator's getAllocationTargets function to include sidecar logic
    /// @param gauge Address of the Curve gauge
    /// @return targets Array of target addresses for the allocation
    function getAllocationTargets(address gauge) public view override returns (address[] memory) {
        address sidecar = CONVEX_SIDECAR_FACTORY.sidecar(gauge);

        /// 2. If the sidecar is not set, return the default targets.
        if (sidecar == address(0)) {
            return super.getAllocationTargets(gauge);
        }

        /// 3. Return the targets.
        address[] memory targets = new address[](2);
        targets[0] = sidecar;
        targets[1] = LOCKER;

        return targets;
    }

    /// @notice Returns the optimal amount of LP token that must be held by Stake DAO Locker
    /// @dev Calculates the optimal balance based on the ratio of veBoost between Stake DAO and Convex
    /// @param gauge Address of the Curve gauge
    /// @return balanceOfLocker Optimal amount of LP token that should be held by Stake DAO Locker
    function getOptimalLockerBalance(address gauge) public view returns (uint256 balanceOfLocker) {
        // 1. Get the balance of veBoost on Stake DAO and Convex
        uint256 veBoostOfLocker = IBalanceProvider(BOOST_DELEGATION_V3).balanceOf(LOCKER);
        uint256 veBoostOfConvex = IBalanceProvider(BOOST_DELEGATION_V3).balanceOf(CONVEX_BOOST_HOLDER);

        // 2. Get the balance of the liquidity gauge on Convex
        uint256 balanceOfConvex = IBalanceProvider(gauge).balanceOf(CONVEX_BOOST_HOLDER);

        // 3. If there is no balance of Convex, return 0
        if (balanceOfConvex == 0) {
            return 0;
        }

        // 4. Compute the optimal balance for Stake DAO
        balanceOfLocker = balanceOfConvex.mulDiv(veBoostOfLocker, veBoostOfConvex);
    }
}
