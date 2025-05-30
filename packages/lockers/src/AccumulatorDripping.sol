// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {AccumulatorBase} from "src/AccumulatorBase.sol";

/// @title AccumulatorDripping
/// @notice Abstract contract for distributing ERC20 rewards over a fixed number of weekly steps,
///         each step making an equal share of the available balance claimable. Designed for gas efficiency,
///         modularity, and predictable reward flows.
/// @dev
/// - Distributes rewards in equal weekly steps (aligned to EVM week boundaries).
/// - Distribution state is packed for gas efficiency.
/// - New distribution can only start when the previous is over and balance is nonzero.
/// - At each step, claimable reward = current balance / remaining steps.
/// - Missed steps are not compounded; distribution resumes at the next eligible call.
/// - Additional tokens sent during an active distribution are included in future steps.
/// - No overlapping distributions; last step drains remaining balance.
/// - Inheriting contract must call `advanceDistributionStep()` after distributing.
///
/// Example usage:
/// ```solidity
/// function claimReward() external {
///     uint256 reward = calculateDistributableReward();
///     require(reward > 0, "No reward available");
///     _sendReward(msg.sender, reward);
///     advanceDistributionStep();
/// }
/// ```
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
abstract contract AccumulatorDripping is AccumulatorBase {
    ///////////////////////////////////////////////////////////////
    /// --- IMMUTABLES
    ///////////////////////////////////////////////////////////////

    /// @notice A fixed-length interval defining by how many active weeks the reward is dripped equally.
    uint256 public immutable PERIOD_LENGTH;

    ///////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////

    /// @notice The parameters of the current distribution.
    /// @dev Packed into 1 storage slot to save gas.
    struct Distribution {
        uint120 timestamp; // distribution start timestamp
        uint120 nextStepTimestamp; // timestamp of the next step of the distribution
        uint16 remainingSteps; // remaining steps before the distribution is over
    }

    /// @notice The parameters of the current distribution.
    Distribution public distribution;

    ///////////////////////////////////////////////////////////////
    /// --- EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when a new distribution starts.
    event DistributionStarted(uint256 timestamp, uint256 periodLength);

    /// @notice Emitted when a new distribution step starts.
    event NewDistributionStepStarted(uint256 nextStepTimestamp, uint16 remainingSteps);

    ///////////////////////////////////////////////////////////////
    /// --- ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when the period length is 0.
    error PERIOD_LENGTH_IS_ZERO();

    /// @notice Error emitted when the distribution is not over yet.
    error DISTRIBUTION_NOT_OVER();

    /// @notice Error emitted when the distribution is not started yet.
    error DISTRIBUTION_NOT_STARTED();

    /// @notice Error emitted when the distribution is already over.
    error DISTRIBUTION_ALREADY_OVER();

    /// @notice Error emitted when there is no balance to distribute for the new distribution.
    error NO_REWARDS_TO_DISTRIBUTE();

    /// @notice Error emitted when the step is already distributed.
    error STEP_ALREADY_DISTRIBUTED();

    ///////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @notice Initializes the AccumulatorDripping and the AccumulatorBase
    /// @param _gauge Address of the sdPENDLE-gauge contract
    /// @param _rewardToken Address of the reward token
    /// @param _locker Address of the Stake DAO Pendle Locker contract
    /// @param _governance Address of the governance contract
    /// @param _periodLength The length of the distribution in weeks
    constructor(address _gauge, address _rewardToken, address _locker, address _governance, uint256 _periodLength)
        AccumulatorBase(_gauge, _rewardToken, _locker, _governance)
    {
        if (_periodLength == 0) revert PERIOD_LENGTH_IS_ZERO();
        PERIOD_LENGTH = _periodLength;
    }

    ///////////////////////////////////////////////////////////////
    /// --- PRIVATE FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Get the current distribution state.
    /// @return distributionTimestamp The start timestamp of the current distribution.
    /// @return nextStepTimestamp The next claimable timestamp of the current distribution.
    /// @return remainingSteps The remaining periods of the current distribution.
    function _getCurrentDistribution()
        private
        view
        returns (uint256 distributionTimestamp, uint256 nextStepTimestamp, uint16 remainingSteps)
    {
        Distribution memory _distribution = distribution;

        distributionTimestamp = uint256(_distribution.timestamp);
        nextStepTimestamp = uint256(_distribution.nextStepTimestamp);
        remainingSteps = _distribution.remainingSteps;
    }

    ///////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Get the current week start timestamp.
    /// @return weekStart The start timestamp of the current week.
    function getCurrentWeekTimestamp() internal view returns (uint256) {
        return (block.timestamp / 1 weeks) * 1 weeks;
    }

    /// @notice Get the current reward token balance.
    /// @return balance The current reward token balance.
    function getCurrentRewardTokenBalance() internal view virtual returns (uint256 balance) {
        balance = ERC20(rewardToken).balanceOf(address(this));
    }

    /// @notice Start a new distribution.
    /// @dev This function must be called once the distribution of the current distribution is done.
    /// @custom:throws will throw if the distribution is still ongoing.
    /// @custom:throws will throw if there is no balance to distribute for the new distribution.
    function startNewDistribution() internal {
        (,, uint16 remainingSteps) = _getCurrentDistribution();

        // If the current distribution is not over yet, revert
        if (remainingSteps > 0) revert DISTRIBUTION_NOT_OVER();

        // If there is no balance to distribute for the new distribution, revert
        if (getCurrentRewardTokenBalance() == 0) revert NO_REWARDS_TO_DISTRIBUTE();

        // Initialize the new distribution state
        uint120 currentWeekTimestamp = uint120(getCurrentWeekTimestamp());
        distribution.timestamp = currentWeekTimestamp;
        distribution.nextStepTimestamp = currentWeekTimestamp;
        distribution.remainingSteps = uint16(PERIOD_LENGTH);

        emit DistributionStarted(currentWeekTimestamp, PERIOD_LENGTH);
    }

    /// @notice Move to the next distribution step.
    /// @dev This function must be called once the distribution of the current step is done.
    /// @custom:throws will throw if the distribution is already over because of the subtraction of the remaining periods.
    function advanceDistributionStep() internal {
        (uint256 distributionTimestamp, uint256 nextStepTimestamp, uint16 remainingSteps) = _getCurrentDistribution();

        if (distributionTimestamp == 0) revert DISTRIBUTION_NOT_STARTED();
        if (remainingSteps == 0) revert DISTRIBUTION_ALREADY_OVER();
        if (block.timestamp < nextStepTimestamp) revert STEP_ALREADY_DISTRIBUTED();

        // Calculate the next claimable timestamp and remaining periods
        nextStepTimestamp = getCurrentWeekTimestamp() + 1 weeks;
        remainingSteps -= 1;

        // Update the distribution state
        distribution.nextStepTimestamp = uint120(nextStepTimestamp);
        distribution.remainingSteps = uint16(remainingSteps);

        emit NewDistributionStepStarted(nextStepTimestamp, remainingSteps);
    }

    /// @notice Calculate the reward available for claiming.
    /// @return reward The reward available for claiming.
    /// @dev 1. The reward per step is calculated as the current contract balance divided by the number of remaining periods.
    ///      This means:
    ///      - If there is any rounding in previous steps, the last step will always distribute the remaining balance,
    ///        ensuring the contract is fully drained by the end of the distribution.
    ///      - If additional reward tokens are sent to this contract during an active distribution,
    ///        those tokens will be included in the distribution for the remaining steps.
    ///
    ///      2. The balance of `rewardToken` is used to calculate the current claimable reward. The `rewardToken` address
    ///      is the one passed to the constructor of this contract and stored by the `AccumulatorBase` contract.
    ///
    ///      3. ⚠︎ This function do not automatically move to the next step of the distribution. If the reward are transferred,
    ///          it is the responsibility of the caller to call `advanceDistributionStep` to move to the next step.
    function calculateDistributableReward() internal view returns (uint256 reward) {
        (, uint256 nextStepTimestamp, uint16 remainingSteps) = _getCurrentDistribution();

        // If the distribution is over, return 0
        if (remainingSteps == 0) return 0;

        // If the current week timestamp is before the next claimable timestamp, return 0
        uint256 currentWeekTimestamp = getCurrentWeekTimestamp();
        if (currentWeekTimestamp < nextStepTimestamp) return 0;

        // Calculate the reward available for claiming
        reward = getCurrentRewardTokenBalance() / remainingSteps;
    }

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Get the remaining steps of the current distribution.
    /// @return remainingSteps The remaining steps of the current distribution.
    function getRemainingSchedule() public view returns (uint16) {
        return distribution.remainingSteps;
    }
}
