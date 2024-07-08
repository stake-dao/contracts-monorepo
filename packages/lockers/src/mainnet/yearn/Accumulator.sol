// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/accumulator/BaseAccumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {IYearnStrategy} from "src/common/interfaces/IYearnStrategy.sol";

/// @title YFI BaseAccumulator
/// @author StakeDAO
contract Accumulator is BaseAccumulator {
    /// @notice YFI token address
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    /// @notice DFYI token address
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance)
        BaseAccumulator(_gauge, DYFI, _locker, _governance)
    {
        strategy = 0x1be150a35bb8233d092747eBFDc75FB357c35168;
        SafeTransferLib.safeApprove(YFI, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(DYFI, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool notifySDT, bool claimFeeStrategy) external override {
        IYearnStrategy(strategy).claimNativeRewards();
        IYearnStrategy(strategy).claimDYFIRewardPool();

        // Sending strategy fees to fee receiver
        if (claimFeeStrategy) {
            _claimFeeStrategy();
        }

        notifyReward(YFI, false, false);
        notifyReward(DYFI, notifySDT, claimFeeStrategy);
    }

    function name() external pure override returns (string memory) {
        return "YFI Accumulator";
    }
}
