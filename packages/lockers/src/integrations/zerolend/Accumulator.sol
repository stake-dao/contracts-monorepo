// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Enum} from "@safe/contracts/common/Enum.sol";
import {Common} from "address-book/src/CommonLinea.sol";
import {ZeroLocker} from "address-book/src/ZeroLinea.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {ISafeLocker} from "src/interfaces/ISafeLocker.sol";
import {IZeroVp} from "src/interfaces/IZeroVp.sol";

/// @title StakeDAO ZERO Accumulator
/// @notice A contract that accumulates ZERO rewards and notifies them to the sdZERO gauge
/// @author StakeDAO
/// @custom:contact contact@stakedao.org

contract ZeroLendAccumulator is AccumulatorBase {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice ZERO token address.
    address public constant ZERO = ZeroLocker.TOKEN;

    /// @notice WETH token address.
    address public constant WETH = Common.WETH;

    /// @notice ZEROvp (veToken) address.
    address public constant ZERO_VP = ZeroLocker.VE_ZERO;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    error ExecFromSafeModuleFailed();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge SD gauge.
    /// @param _locker SD locker.
    /// @param _governance Governance.
    /// @dev Gives unlimited approval to the gauge for each reward token.
    constructor(address _gauge, address _locker, address _governance)
        AccumulatorBase(_gauge, ZERO, _locker, _governance)
    {
        SafeTransferLib.safeApprove(ZERO, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(WETH, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4.
    function claimAndNotifyAll() external override {
        uint256 lockerZeroBalanceBefore = IERC20(ZERO).balanceOf(locker);
        uint256 lockerWethBalanceBefore = IERC20(WETH).balanceOf(locker);

        // Claim rewards from the locker.
        bool _success;
        (_success,) = ISafeLocker(locker).execTransactionFromModuleReturnData(
            ZERO_VP, 0, abi.encodeWithSelector(IZeroVp.getReward.selector), Enum.Operation.Call
        );

        if (!_success) revert ExecFromSafeModuleFailed();

        // Get rewards amount.
        uint256 zeroReward = IERC20(ZERO).balanceOf(locker) - lockerZeroBalanceBefore;
        uint256 wethReward = IERC20(WETH).balanceOf(locker) - lockerWethBalanceBefore;

        // Transfer rewards to the accumulator.
        if (zeroReward > 0) {
            (_success,) = ISafeLocker(locker).execTransactionFromModuleReturnData(
                ZERO,
                0,
                abi.encodeWithSelector(IERC20.transfer.selector, address(this), zeroReward),
                Enum.Operation.Call
            );
            if (!_success) revert ExecFromSafeModuleFailed();

            notifyReward(ZERO);
        }

        if (wethReward > 0) {
            (_success,) = ISafeLocker(locker).execTransactionFromModuleReturnData(
                WETH,
                0,
                abi.encodeWithSelector(IERC20.transfer.selector, address(this), wethReward),
                Enum.Operation.Call
            );
            if (!_success) revert ExecFromSafeModuleFailed();

            notifyReward(WETH);
        }
    }

    function name() external pure override returns (string memory) {
        return "ZERO Accumulator";
    }
}
