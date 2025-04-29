// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/accumulator/BaseAccumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";

/// @title APW Accumulator V3
/// @author StakeDAO
contract Accumulator is BaseAccumulator {
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
        BaseAccumulator(_gauge, APW, _locker, _governance)
    {
        SafeTransferLib.safeApprove(APW, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll() external override {
        ILocker(locker).claimRewards(APW, address(this));

        // Sending strategy fees to fee receiver
        _claimFeeStrategy();

        notifyReward(APW, true, true);
    }

    function name() external pure override returns (string memory) {
        return "APW Accumulator";
    }
}
