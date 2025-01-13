// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/accumulator/BaseAccumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";

/// @notice A contract that accumulates FXN rewards and notifies them to the sdFXN gauge
/// @author StakeDAO
contract Accumulator is BaseAccumulator {
    /// @notice ZEROlp token address.
    address public constant ZERO_LP = 0x0040F36784dDA0821E74BA67f86E084D70d67a3A;

    /// @notice Fee distributor address.
    address public constant ZERO_LP_VP = 0x0374ae8e866723ADAE4A62DcE376129F292369b4;

    // WETH token
    address public constant REWARD_TOKEN = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance)
        BaseAccumulator(_gauge, REWARD_TOKEN, _locker, _governance)
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
        ILocker(locker).claimRewards(ZERO_LP_VP, REWARD_TOKEN, address(this));

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
