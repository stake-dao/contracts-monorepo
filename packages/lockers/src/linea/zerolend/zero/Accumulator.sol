// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/accumulator/BaseAccumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";

/// @notice A contract that accumulates FXN rewards and notifies them to the sdFXN gauge
/// @author StakeDAO
contract Accumulator is BaseAccumulator {
    /// @notice ZERO token address.
    address public constant ZERO = 0x78354f8DcCB269a615A7e0a24f9B0718FDC3C7A7;

    /// @notice Fee distributor address.
    address public constant ZERO_VP = 0xf374229a18ff691406f99CCBD93e8a3f16B68888;

    // ZERO token
    address public constant REWARD_TOKEN = ZERO;

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
        SafeTransferLib.safeApprove(REWARD_TOKEN, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    // TODO do we remove the notifySDT variable since we will be using the LiquidityGaugeV4XChain
    //      we could also set it to false directly below?
    function claimAndNotifyAll(bool notifySDT, bool claimFeeStrategy) external override {
        ILocker(locker).claimRewards(ZERO_VP, REWARD_TOKEN, address(this));

        // TODO should remove this right?
        // /// Claim Extra FXN rewards.
        // if (claimFeeStrategy && strategy != address(0)) {
        //     _claimFeeStrategy();
        // }

        notifyReward(REWARD_TOKEN, notifySDT, claimFeeStrategy);
    }

    function name() external pure override returns (string memory) {
        return "ZERO Accumulator";
    }
}
