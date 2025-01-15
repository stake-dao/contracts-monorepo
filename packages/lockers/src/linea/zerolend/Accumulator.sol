// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/accumulator/BaseAccumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice A contract that accumulates FXN rewards and notifies them to the sdFXN gauge
/// @author StakeDAO
contract Accumulator is BaseAccumulator {
    /// @notice ZERO token address.
    address public constant ZERO = 0x78354f8DcCB269a615A7e0a24f9B0718FDC3C7A7;

    // @notice WETH token address.
    address public constant WETH = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;

    /// @notice Fee distributor address.
    address public constant ZERO_VP = 0xf374229a18ff691406f99CCBD93e8a3f16B68888;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance)
        BaseAccumulator(_gauge, ZERO, _locker, _governance)
    {
        SafeTransferLib.safeApprove(ZERO, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(WETH, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    // TODO natspecs
    function claimAndNotifyAll(bool notifySDT, bool claimFeeStrategy) external override {
        // claim rewards from the locker
        ILocker(locker).execute(ZERO_VP, 0, abi.encodeWithSignature("getReward()"));

        // transfer rewards to the gauge
        ILocker(locker).execute(
            ZERO, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), IERC20(ZERO).balanceOf(locker))
        );
        ILocker(locker).execute(
            WETH, 0, abi.encodeWithSignature("transfer(address,uint256)", address(this), IERC20(WETH).balanceOf(locker))
        );

        notifyReward(ZERO, notifySDT, claimFeeStrategy);
        notifyReward(WETH, notifySDT, claimFeeStrategy);
    }

    function name() external pure override returns (string memory) {
        return "ZERO Accumulator";
    }
}
