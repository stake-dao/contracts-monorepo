// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/accumulator/AccumulatorV2.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {IYieldDistributor} from "src/base/interfaces/IYieldDistributor.sol";

/// @title A contract that accumulates FXS rewards and notifies them to the LGV4
/// @author StakeDAO
contract FxsAccumulatorFraxtal is AccumulatorV2 {
    /// @notice FXS token address
    address public constant FXS = 0xFc00000000000000000000000000000000000002;

    /// @notice FXS ethereum locker
    address public constant ETH_LOCKER = 0xCd3a267DE09196C48bbB1d9e842D7D7645cE448f;

    /// @notice FXS yield distributor
    address public yieldDistributor = 0x21359d1697e610e25C8229B2C57907378eD09A2E;

    /// @notice Strategy address
    address public strategy;

    /// @notice Throwed when a low level call fails
    error CallFailed();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge sd gauge
    /// @param _locker sd locker
    /// @param _governance governance
    /// @param _delegationRegistry delegation registry
    /// @param _initialDelegate initial delegate
    constructor(
        address _gauge,
        address _locker,
        address _governance,
        address _delegationRegistry,
        address _initialDelegate
    ) AccumulatorV2(_gauge, _locker, _governance) {
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
    /// @param _claimStrategyFee if claim or not strategy fees
    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll(bool _notifySDT, bool _pullFromFeeSplitter, bool _claimStrategyFee) external override {
        // Sending strategy fees to fee receiver
        if (_claimStrategyFee && strategy != address(0)) {
            _claimFeeStrategy(strategy);
        }

        /// Claim FXS reward for L1's veFXS bridged, on behalf of the eth locker
        IYieldDistributor(yieldDistributor).getYieldThirdParty(ETH_LOCKER);

        /// Claim FXS reward for fraxtal's veFXS
        ILocker(locker).claimRewards(yieldDistributor, FXS, address(this));

        /// Notify FXS to the gauge.
        notifyReward(FXS, _notifySDT, _pullFromFeeSplitter);
    }

    /// @notice Set frax yield distributor
    /// @param _yieldDistributor Address of the frax yield distributor
    function setYieldDistributor(address _yieldDistributor) external onlyGovernance {
        yieldDistributor = _yieldDistributor;
    }

    /// @notice Set strategy
    /// @param _strategy Address of the strategy
    function setStrategy(address _strategy) external onlyGovernance {
        strategy = _strategy;
    }
}
