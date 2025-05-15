// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SpectraProtocol} from "address-book/src/SpectraBase.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {ISpectraRewardsDistributor} from "src/common/interfaces/spectra/spectra/ISpectraRewardsDistributor.sol";
import {ISdSpectraDepositor} from "src/common/interfaces/spectra/stakedao/ISdSpectraDepositor.sol";

/// @title StakeDAO SPECTRA Accumulator
/// @notice A contract that accumulates SPECTRA rewards and notifies them to the sdSPECTRA gauge
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Accumulator is BaseAccumulator {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice SPECTRA Rewards distributor address.
    ISpectraRewardsDistributor public constant rewardsDistributor =
        ISpectraRewardsDistributor(SpectraProtocol.FEE_DISTRIBUTOR);

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////

    /// @notice sdSPECTRA depositor address.
    address public immutable depositor;

    /// @notice sdSPECTRA address.
    address public immutable sdSPECTRA;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge SD gauge.
    /// @param _locker SD locker.
    /// @param _governance Governance.
    /// @param _sdSPECTRA sdSPECTRA.
    /// @param _depositor SD depositor.
    /// @dev Gives unlimited approval to the gauge for each reward token and sets required variables.
    constructor(address _gauge, address _sdSPECTRA, address _locker, address _governance, address _depositor)
        BaseAccumulator(_gauge, _sdSPECTRA, _locker, _governance)
    {
        SafeTransferLib.safeApprove(_sdSPECTRA, _gauge, type(uint256).max);
        sdSPECTRA = _sdSPECTRA;
        depositor = _depositor;
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4.
    function claimAndNotifyAll() external override {
        // If SPECTRA are available for rebasing, trigger rebase
        if (rewardsDistributor.claimable(ISdSpectraDepositor(depositor).spectraLockedTokenId()) > 0) {
            rewardsDistributor.claim(ISdSpectraDepositor(depositor).spectraLockedTokenId());
        }
        // Call depositor to mint rewards
        ISdSpectraDepositor(depositor).mintRewards();

        // Notify rewards, sending them to the liquidity gauge
        notifyReward(sdSPECTRA);
    }

    function name() external pure override returns (string memory) {
        return "SPECTRA Accumulator";
    }
}
