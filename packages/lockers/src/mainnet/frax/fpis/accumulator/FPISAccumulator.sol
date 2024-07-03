// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/accumulator/Accumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";

/// @title FPIS Accumulator V3
/// @author StakeDAO
contract FPISAccumulator is Accumulator {
    /// @notice FXS token address
    address public constant FPIS = 0xc2544A32872A91F4A553b404C6950e89De901fdb;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance) Accumulator(_gauge, FPIS, _locker, _governance) {
        SafeTransferLib.safeApprove(FPIS, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool notifySDT, bool, bool claimFeeStrategy) external override {
        ILocker(locker).claimFPISRewards(address(this));

        // Sending strategy fees to fee receiver
        if (claimFeeStrategy) {
            _claimFeeStrategy();
        }

        notifyReward(FPIS, notifySDT, claimFeeStrategy);
    }
}
