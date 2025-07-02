// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Common} from "@address-book/src/CommonEthereum.sol";
import {FXNProtocol} from "@address-book/src/FXNEthereum.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {ILocker} from "src/interfaces/ILocker.sol";

/// @notice A contract that accumulates FXN rewards and notifies them to the sdFXN gauge
/// @author StakeDAO

contract FXNAccumulator is AccumulatorBase {
    /// @notice FXN token address.
    address public constant FXN = FXNProtocol.FXN;

    /// @notice WSTETH token address.
    address public constant WSTETH = Common.WSTETH;

    /// @notice Fee distributor address.
    // TODO: Double check this address.
    address public constant FEE_DISTRIBUTOR = 0xd116513EEa4Efe3908212AfBAeFC76cb29245681;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    constructor(address _gauge, address _locker, address _governance)
        AccumulatorBase(_gauge, WSTETH, _locker, _governance)
    {
        SafeTransferLib.safeApprove(FXN, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(WSTETH, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll() external override {
        ILocker(locker).claimRewards(FEE_DISTRIBUTOR, WSTETH, address(this));

        /// Claim Extra FXN rewards.
        if (accountant != address(0)) _claimAccumulatedFee();

        notifyReward(WSTETH);
    }

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    function version() external pure virtual override returns (string memory) {
        return "4.0.0";
    }

    function name() external view virtual override returns (string memory) {
        return type(FXNAccumulator).name;
    }
}
