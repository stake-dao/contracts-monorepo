// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/accumulator/Accumulator.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";

/// @title FXS Accumulator V3
/// @author StakeDAO
contract FXSAccumulator is Accumulator {
    /// @notice FXS token address
    address public constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance) Accumulator(_gauge, FXS, _locker, _governance) {
        SafeTransferLib.safeApprove(FXS, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool notifySDT, bool, bool claimFeeStrategy) external override {
        ILocker(locker).claimFXSRewards(address(this));

        // Sending strategy fees to fee receiver
        if (claimFeeStrategy) {
            _claimFeeStrategy();
        }

        notifyReward(FXS, notifySDT, claimFeeStrategy);
    }
}
