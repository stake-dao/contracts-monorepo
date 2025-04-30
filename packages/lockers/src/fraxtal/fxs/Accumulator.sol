// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/accumulator/BaseAccumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {IYieldDistributor} from "src/common/interfaces/IYieldDistributor.sol";
import "src/fraxtal/FXTLDelegation.sol";

/// @title A contract that accumulates FXS rewards and notifies them to the LGV4
/// @author StakeDAO
contract Accumulator is BaseAccumulator, FXTLDelegation {
    /// @notice FXS token address
    address public constant FXS = 0xFc00000000000000000000000000000000000002;

    /// @notice FXS ethereum locker
    address public constant ETH_LOCKER = 0xCd3a267DE09196C48bbB1d9e842D7D7645cE448f;

    /// @notice FXS yield distributor
    address public yieldDistributor = 0x21359d1697e610e25C8229B2C57907378eD09A2E;

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
    ) BaseAccumulator(_gauge, FXS, _locker, _governance) FXTLDelegation(_delegationRegistry, _initialDelegate) {
        SafeTransferLib.safeApprove(FXS, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll() external override {
        // Sending accountant fees to fee receiver
        if (accountant != address(0)) {
            _claimAccumulatedFee();
        }

        /// Claim FXS reward for L1's veFXS bridged, on behalf of the eth locker
        IYieldDistributor(yieldDistributor).getYieldThirdParty(ETH_LOCKER);

        /// Claim FXS reward for fraxtal's veFXS
        ILocker(locker).claimRewards(yieldDistributor, FXS, address(this));

        /// Notify FXS to the gauge.
        notifyReward(FXS, true, true);
    }

    /// @notice Set frax yield distributor
    /// @param _yieldDistributor Address of the frax yield distributor
    function setYieldDistributor(address _yieldDistributor) external onlyGovernance {
        yieldDistributor = _yieldDistributor;
    }
}
