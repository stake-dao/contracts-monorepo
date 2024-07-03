// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/accumulator/Accumulator.sol";
import {ILocker} from "src/common/interfaces/ILocker.sol";
import {IStrategy} from "herdaddy/interfaces/stake-dao/IStrategy.sol";
import {IPendleFeeDistributor} from "src/common/interfaces/IPendleFeeDistributor.sol";

interface IWETH {
    function deposit() external payable;
}

/// @title PENDLEAccumulator - Accumulator for Pendle
/// @author StakeDAO
contract PENDLEAccumulator is Accumulator {
    /// @notice Base fee (10_000 = 100%)
    uint256 private constant BASE_FEE = 10_000;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
    address public constant VE_PENDLE = 0x4f30A9D41B80ecC5B94306AB4364951AE3170210;
    address public constant FEE_DISTRIBUTOR = 0x8C237520a8E14D658170A633D96F8e80764433b9;

    /// @notice WETH Distribution fee.
    uint256 public periodsToAdd = 4;

    /// @notice WETH Rewards period to notify.
    uint256 public remainingPeriods;

    /// @notice If false, the voters rewards will be distributed to the gauge
    bool public transferVotersRewards;

    /// @notice Address to receive the voters rewards.
    address public votesRewardRecipient;

    /// @notice Rewards for the period.
    mapping(uint256 => uint256) public rewards; // period -> reward amount

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when a token not supported is used.
    error WRONG_TOKEN();

    /// @notice Error emitted when there is no balance to claim.
    error NO_REWARD();

    /// @notice Error emitted when there is no balance to claim.
    error NO_BALANCE();

    /// @notice Error emitted when the claim is not successful.
    error NOT_CLAIMED_ALL();

    /// @notice Error emitted when the reward is ongoing.
    error ONGOING_REWARD();

    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    constructor(address _gauge, address _locker, address _governance) Accumulator(_gauge, WETH, _locker, _governance) {
        SafeTransferLib.safeApprove(WETH, gauge, type(uint256).max);
        SafeTransferLib.safeApprove(PENDLE, gauge, type(uint256).max);
    }

    function claimAndNotifyAll(address[] memory _pools, bool notifySDT, bool pullFromFeeReceiver, bool claimFeeStrategy)
        external
    {
        // Sending strategy fees to fee receiver
        if (claimFeeStrategy && strategy != address(0)) {
            _claimFeeStrategy();
        }

        /// Check historical rewards.
        uint256 totalAccrued = IPendleFeeDistributor(FEE_DISTRIBUTOR).getProtocolTotalAccrued(address(locker));

        /// Check claimed rewards.
        uint256 claimed = IPendleFeeDistributor(FEE_DISTRIBUTOR).claimed(address(locker));

        address[] memory vePendle = new address[](1);
        vePendle[0] = VE_PENDLE;

        /// Check the native reward claimable.
        uint256 nativeRewardClaimable =
            IPendleFeeDistributor(FEE_DISTRIBUTOR).getProtocolClaimables(address(locker), vePendle)[0];

        /// Claim on behalf of the locker.
        uint256 totalReward = _claimReward(_pools);

        /// There's 1e4 wei of tolerance to avoid rounding errors because of a mistake in the Pendle FEE_DISTRIBUTOR contract.
        if (totalReward + 1e4 < totalAccrued - claimed) revert NOT_CLAIMED_ALL();

        /// Update the remaining periods.
        remainingPeriods += periodsToAdd;

        /// Charge fee on the total reward.
        totalReward -= _chargeFee(WETH, totalReward);

        /// If the voters rewards are not transferred to the recipient, they will be distributed to the gauge.
        if (transferVotersRewards) {
            uint256 votersTotalReward = totalReward - nativeRewardClaimable;
            // transfer the amount without charging fees
            SafeTransferLib.safeTransfer(WETH, votesRewardRecipient, votersTotalReward);
        }

        /// We put 0 as the amount to notify, as it'll distribute the balance.
        _notifyReward(WETH, 0, false);
        _notifyReward(PENDLE, 0, pullFromFeeReceiver);

        /// Just in case, but it should be needed anymore.
        if (notifySDT) {
            _distributeSDT();
        }
    }

    /// @notice Notify the new reward to the LGV4
    /// @param _tokenReward token to notify
    /// @param _amount amount to notify
    /// @param _pullFromFeeReceiver if pull tokens from the fee receiver or not (tokens already in that contract)
    function _notifyReward(address _tokenReward, uint256 _amount, bool _pullFromFeeReceiver) internal override {
        if (_pullFromFeeReceiver && feeReceiver != address(0)) {
            // Split fees for the specified token using the fee receiver contract
            // Function not permissionless, to prevent sending to that accumulator and re-splitting (_chargeFee)
            IFeeReceiver(feeReceiver).split(_tokenReward);
        }

        if (_tokenReward == WETH && remainingPeriods != 0) {
            uint256 currentWeek = block.timestamp * 1 weeks / 1 weeks;
            if (rewards[currentWeek] != 0) revert ONGOING_REWARD();

            _amount = ERC20(WETH).balanceOf(address(this)) / remainingPeriods;
            rewards[currentWeek] = _amount;

            remainingPeriods -= 1;
        } else {
            _amount = ERC20(_tokenReward).balanceOf(address(this));
        }

        if (_amount == 0) return;
        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);
    }

    /// @notice Claim reward for the pools
    /// @param _pools pools to claim the rewards
    function _claimReward(address[] memory _pools) internal returns (uint256 claimed) {
        uint256 balanceBefore = address(this).balance;
        ILocker(locker).claimRewards(address(this), _pools);

        // Wrap Eth to WETH
        claimed = address(this).balance - balanceBefore;
        if (claimed == 0) revert NO_BALANCE();
        IWETH(WETH).deposit{value: address(this).balance}();
    }

    function setVotesRewardRecipient(address _votesRewardRecipient) external onlyGovernance {
        votesRewardRecipient = _votesRewardRecipient;
    }

    function setTransferVotersRewards(bool _transferVotersRewards) external onlyGovernance {
        transferVotersRewards = _transferVotersRewards;
    }

    function setPeriodsToAdd(uint256 _periodsToAdd) external onlyGovernance {
        periodsToAdd = _periodsToAdd;
    }
}
