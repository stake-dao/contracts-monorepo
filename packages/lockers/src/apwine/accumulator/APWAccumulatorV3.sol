// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/accumulator/AccumulatorV2.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";

/// @title FPIS Accumulator V3
/// @author StakeDAO
contract APWAccumulatorV3 is AccumulatorV2 {
    /// @notice FXS token address
    address public constant APW = 0x4104b135DBC9609Fc1A9490E61369036497660c8;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance)
        AccumulatorV2(_gauge, APW, _locker, _governance)
    {
        SafeTransferLib.safeApprove(APW, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool notifySDT, bool, bool claimFeeStrategy) external override {
        ILocker(locker).claimRewards(APW, address(this));

        // Sending strategy fees to fee receiver
        if (claimFeeStrategy) {
            _claimFeeStrategy();
        }

        notifyReward(APW, notifySDT, claimFeeStrategy);
    }
}
