// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/interfaces/IVeBoost.sol";
import "src/common/interfaces/IVeBoostDelegation.sol";

import "src/common/accumulator/BaseAccumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";

/// @notice BAL BaseAccumulator
/// @author StakeDAO
contract Accumulator is BaseAccumulator {
    /// @notice BAL token address.
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    /// @notice USDC token address.
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice VeBAL token address.
    address public constant VE_BAL = 0xC128a9954e6c874eA3d62ce62B468bA073093F25;

    /// @notice Ve Boost.
    IVeBoost public veBoost = IVeBoost(0x67F8DF125B796B05895a6dc8Ecf944b9556ecb0B);

    /// @notice Ve Boost FXTLDelegation.
    IVeBoostDelegation public veBoostDelegation = IVeBoostDelegation(0xda9846665Bdb44b0d0CAFFd0d1D4A539932BeBdf);

    uint256 public multiplier;

    constructor(address _gauge, address _locker, address _governance)
        BaseAccumulator(_gauge, USDC, _locker, _governance)
    {
        SafeTransferLib.safeApprove(BAL, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(USDC, _gauge, type(uint256).max);
    }

    function claimAndNotifyAll(bool notifySDT, bool, bool claimFeeStrategy) external override {
        ILocker(locker).claimRewards(USDC, address(this));

        // Claim Extra USDC rewards.
        if (claimFeeStrategy) {
            _claimFeeStrategy();
        }

        notifyReward(USDC, false, false);
        notifyReward(BAL, notifySDT, claimFeeStrategy);
    }

    function _notifyReward(address _tokenReward, uint256 _amount, bool _pullFromFeeReceiver) internal override {
        _chargeFee(_tokenReward, _amount);

        if (_pullFromFeeReceiver && feeReceiver != address(0)) {
            // Split fees for the specified token using the fee receiver contract
            // Function not permissionless, to prevent sending to that accumulator and re-splitting (_chargeFee)
            IFeeReceiver(feeReceiver).split(_tokenReward);
        }

        _amount = ERC20(_tokenReward).balanceOf(address(this));

        /// Share the BAL rewards with the delegation contract.
        _amount -= _shareWithDelegation();

        if (_amount == 0) return;
        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);
    }

    /// @notice Share the BAL Rewards from Strategy
    function _shareWithDelegation() internal returns (uint256 delegationShare) {
        uint256 amount = ERC20(BAL).balanceOf(address(this));
        if (amount == 0) return 0;
        if (address(veBoost) == address(0) || address(veBoostDelegation) == address(0)) return 0;

        /// Share the BAL rewards with the delegation contract.
        uint256 boostReceived = veBoost.received_balance(locker);
        if (boostReceived == 0) return 0;

        /// Get the VeBAL balance of the locker.
        uint256 lockerVeBal = ERC20(VE_BAL).balanceOf(locker);

        /// Calculate the percentage of BAL delegated to the VeBoost contract.
        uint256 bpsDelegated = (boostReceived * DENOMINATOR / lockerVeBal);

        /// Calculate the expected delegation share.
        delegationShare = amount * bpsDelegated / DENOMINATOR;

        /// Apply the multiplier.
        if (multiplier != 0) {
            delegationShare = delegationShare * multiplier / DENOMINATOR;
        }

        SafeTransferLib.safeTransfer(BAL, address(veBoostDelegation), delegationShare);
    }

    function setMultiplier(uint256 _multiplier) external onlyGovernance {
        multiplier = _multiplier;
    }

    function setVeBoost(address _veBoost) external onlyGovernance {
        veBoost = IVeBoost(_veBoost);
    }

    function setVeBoostDelegation(address _veBoostDelegation) external onlyGovernance {
        veBoostDelegation = IVeBoostDelegation(_veBoostDelegation);
    }
}
