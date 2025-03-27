// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Enum} from "@safe/contracts/common/Enum.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {ILocker} from "src/common/interfaces/zerolend/stakedao/ILocker.sol";
import {IZeroVp} from "src/common/interfaces/zerolend/zerolend/IZeroVp.sol";

/// @title StakeDAO ZERO Accumulator
/// @notice A contract that accumulates ZERO rewards and notifies them to the sdZERO gauge
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Accumulator is BaseAccumulator {
    //////////////////////////////////////////////////////
    // --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice ZERO token address.
    address public constant ZERO = 0x78354f8DcCB269a615A7e0a24f9B0718FDC3C7A7;

    /// @notice WETH token address.
    address public constant WETH = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;

    /// @notice ZEROvp (veToken) address.
    address public constant ZERO_VP = 0xf374229a18ff691406f99CCBD93e8a3f16B68888;

    //////////////////////////////////////////////////////
    // --- ERRORS
    //////////////////////////////////////////////////////

    error ExecFromSafeModuleFailed();

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge SD gauge.
    /// @param _locker SD locker.
    /// @param _governance Governance.
    /// @dev Gives unlimited approval to the gauge for each reward token.
    constructor(address _gauge, address _locker, address _governance)
        BaseAccumulator(_gauge, ZERO, _locker, _governance)
    {
        SafeTransferLib.safeApprove(ZERO, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(WETH, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    // --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4.
    function claimAndNotifyAll(bool, bool) external override {
        uint256 lockerZeroBalanceBefore = IERC20(ZERO).balanceOf(locker);
        uint256 lockerWethBalanceBefore = IERC20(WETH).balanceOf(locker);

        // Claim rewards from the locker.
        bool _success;
        (_success,) = ILocker(locker).execTransactionFromModuleReturnData(
            ZERO_VP, 0, abi.encodeWithSelector(IZeroVp.getReward.selector), Enum.Operation.Call
        );

        if (!_success) revert ExecFromSafeModuleFailed();

        // Get rewards amount.
        uint256 zeroReward = IERC20(ZERO).balanceOf(locker) - lockerZeroBalanceBefore;
        uint256 wethReward = IERC20(WETH).balanceOf(locker) - lockerWethBalanceBefore;

        // Transfer rewards to the accumulator.
        if (zeroReward > 0) {
            (_success,) = ILocker(locker).execTransactionFromModuleReturnData(
                ZERO,
                0,
                abi.encodeWithSelector(IERC20.transfer.selector, address(this), zeroReward),
                Enum.Operation.Call
            );
            if (!_success) revert ExecFromSafeModuleFailed();

            notifyReward(ZERO, false, false);
        }

        if (wethReward > 0) {
            (_success,) = ILocker(locker).execTransactionFromModuleReturnData(
                WETH,
                0,
                abi.encodeWithSelector(IERC20.transfer.selector, address(this), wethReward),
                Enum.Operation.Call
            );
            if (!_success) revert ExecFromSafeModuleFailed();

            notifyReward(WETH, false, false);
        }
    }

    function name() external pure override returns (string memory) {
        return "ZERO Accumulator";
    }
}
