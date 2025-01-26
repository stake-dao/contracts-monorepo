// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/accumulator/BaseAccumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title StakeDAO ZERO Accumulator
/// @notice A contract that accumulates ZERO rewards and notifies them to the sdZERO gauge
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Accumulator is BaseAccumulator {
    /// @notice ZERO token address.
    address public constant ZERO = 0x78354f8DcCB269a615A7e0a24f9B0718FDC3C7A7;

    /// @notice WETH token address.
    address public constant WETH = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;

    /// @notice ZEROvp (veToken) address.
    address public constant ZERO_VP = 0xf374229a18ff691406f99CCBD93e8a3f16B68888;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
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
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4.
    /// @param notifySDT Deactivated, should be false.
    /// @param claimFeeStrategy Deactivated, should be false.
    function claimAndNotifyAll(bool notifySDT, bool claimFeeStrategy) external override {
        // Claim rewards from the locker.
        ILocker(locker).execute(ZERO_VP, 0, abi.encodeWithSignature("getReward()"));

        // Get rewards amount.
        uint256 lockerZeroBalance = IERC20(ZERO).balanceOf(locker);
        uint256 lockerWethBalance = IERC20(WETH).balanceOf(locker);

        // Transfer rewards to the accumulator.
        if (lockerZeroBalance > 0) {
            ILocker(locker).execute(
                ZERO, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), lockerZeroBalance)
            );
        }
        if (lockerWethBalance > 0) {
            ILocker(locker).execute(
                WETH, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), lockerWethBalance)
            );
        }

        // Transfer rewards to the gauge.
        if (lockerZeroBalance > 0) {
            notifyReward(ZERO, notifySDT, claimFeeStrategy);
        }
        if (lockerWethBalance > 0) {
            notifyReward(WETH, notifySDT, claimFeeStrategy);
        }
    }

    function name() external pure override returns (string memory) {
        return "ZERO Accumulator";
    }
}
