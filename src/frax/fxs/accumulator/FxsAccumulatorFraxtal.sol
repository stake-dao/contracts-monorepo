// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/accumulator/Accumulator.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";

/// @title A contract that accumulates FXS rewards and notifies them to the LGV4
/// @author StakeDAO
contract FxsAccumulatorFraxtal is Accumulator {
    /// @notice FXS token address
    address public constant FXS = 0xFc00000000000000000000000000000000000002;

    /// @notice FXS yield distributor
    address public constant YIELD_DISTRIBUTOR = 0x39333a540bbea6262e405E1A6d435Bd2e776561E;

    /// @notice Throwed when a low level call fails
    error CallFailed();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _daoFeeRecipient dao fee recipient
    /// @param _liquidityFeeRecipient liquidity fee recipient
    /// @param _governance governance
    constructor(
        address _gauge,
        address _locker,
        address _daoFeeRecipient,
        address _liquidityFeeRecipient,
        address _governance,
        address _delegationRegistry,
        address _initialDelegate
    ) Accumulator(_gauge, _locker, _daoFeeRecipient, _liquidityFeeRecipient, _governance) {
        SafeTransferLib.safeApprove(FXS, _gauge, type(uint256).max);

        // Custom code for Fraxtal
        // set _initialDelegate as delegate
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert CallFailed();
        // disable self managing delegation
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert CallFailed();
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claim FXS rewards for the locker and notify all to the LGV4
    /// @param _notifySDT if notify SDT or not
    /// @param _pullFromFeeSplitter if pull tokens from the fee splitter or not
    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool _notifySDT, bool _pullFromFeeSplitter) external override {
        /// Claim FXS reward.
        ILocker(locker).claimRewards(YIELD_DISTRIBUTOR, FXS, address(this));

        /// Notify FXS to the gauge.
        notifyReward(FXS, _notifySDT, _pullFromFeeSplitter);
    }
}
