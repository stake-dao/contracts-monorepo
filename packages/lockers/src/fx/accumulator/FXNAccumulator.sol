// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/accumulator/Accumulator.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";

/// @notice A contract that accumulates FXN rewards and notifies them to the sdFXN gauge
/// @author StakeDAO
contract FXNAccumulator is Accumulator {
    /// @notice FXN token address.
    address public constant FXN = 0x365AccFCa291e7D3914637ABf1F7635dB165Bb09;

    /// @notice WSTETH token address.
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @notice Fee distributor address.
    address public constant FEE_DISTRIBUTOR = 0xd116513EEa4Efe3908212AfBAeFC76cb29245681;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance)
        Accumulator(_gauge, WSTETH, _locker, _governance)
    {
        SafeTransferLib.safeApprove(FXN, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(WSTETH, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool notifySDT, bool, bool claimFeeStrategy) external override {
        ILocker(locker).claimRewards(FEE_DISTRIBUTOR, WSTETH, address(this));

        /// Claim Extra FXN rewards.
        if (claimFeeStrategy && strategy != address(0)) {
            _claimFeeStrategy();
        }

        notifyReward(WSTETH, notifySDT, claimFeeStrategy);
    }
}
