# **DrippingAccumulator Contract Specification**

## **Overview**

`DrippingAccumulator` is an abstract contract for time-based, stepwise reward distribution. It enables any inheriting contract to distribute ERC20 rewards over a fixed number of weekly steps (e.g., 4 weeks), with each step distributing an equal share of the available balance at the time of claim. The contract is designed for gas efficiency, modularity, and predictable, auditable reward flows.

## **Key Concepts**

- **Distribution:**
  A distribution is a campaign that splits the contract's reward token balance into a fixed number of steps (weeks). Each step allows a portion of the balance to be distributed.

- **Step:**
  Each step represents a week (aligned to EVM week boundaries, i.e., Thursday 00:00 UTC). At each step, a equalportion of the remaining balance is made available for distribution.

- **State Packing:**
  The distribution state is packed into a single storage slot for gas efficiency.

---

## **Core Data Structures**

```solidity
struct Distribution {
    uint120 timestamp;           // Distribution start timestamp (week-aligned)
    uint120 nextStepTimestamp;   // Timestamp of the next step (week-aligned)
    uint16 remainingSteps;       // Steps left before the distribution is over
}
Distribution public distribution;
```

- **PERIOD_LENGTH:**
  Immutable, set at construction. Defines the number of steps (weeks) in each distribution.

## **Workflow**

### 1. **Starting a New Distribution**

- Only possible when the previous distribution is over (`remainingSteps == 0`).
- Only possible if the contract holds a nonzero balance of the reward token.
- Sets the start and next step timestamps to the current week boundary.
- Sets `remainingSteps` to `PERIOD_LENGTH`.
- Emits `DistributionStarted`.

### 2. **Claiming/Distributing Rewards**

- At each step (week), a equal portion of the current contract balance is made available for distribution.
- The reward per step is calculated as:
  `currentBalance / remainingSteps`
- If the function is called late (after several weeks), only the next step is processed; missed steps are not compounded or skipped. It's like pausing the distribution until the next step is reached.
- ⚠️ After distributing, the contract **mustcall `advanceDistributionStep`** to move to the next step and decrement `remainingSteps`.
- Emits `NewDistributionStepStarted`.

### 3. **Handling Additional Deposits**

- If additional reward tokens are sent to the contract during an active distribution, they are included in the calculation for the remaining steps. This is not an intentional feature, but a side effect of the current implementation.

### 4. **End of Distribution**

- When `remainingSteps` reaches 0, the distribution is over.
- A new distribution can be started with the next available balance.

## **Key Functions**

### **Internal Functions**

Only those functions are intended to be called by the inheriting contract.

- `startNewDistribution()`

  - Starts a new distribution if the previous one is over and there is a nonzero balance.
  - Initializes the distribution state and emits an event.

- `advanceDistributionStep()`

  - Moves to the next step (week) of the current distribution.
  - Increments the `nextStepTimestamp` by 1 week and decrements `remainingSteps`.
  - Emits an event.

- `calculateDistributableReward()`
  - Returns the amount of reward available for the current step.
  - Returns 0 if the distribution is over or if the current week is before the next step timestamp.
  - The reward is always calculated as the current contract balance divided by the number of remaining steps.
  - The balance of `rewardToken` is used to calculate the current claimable reward. The `rewardToken` address is the one passed to the constructor.
  - **Note:** If additional tokens are sent to the contract during an active distribution, they are included in the calculation for the remaining steps.

## **Design Considerations**

- **No Overlap:**
  Distributions cannot overlap. New rewards can only be distributed after the previous distribution is complete.

- **No Catch-Up:**
  If a step is missed (i.e., no claim is made during a week), the system does not catch up or distribute multiple steps at once. The distribution simply resumes at the next eligible call.

- **Rounding:**
  If there is rounding in previous steps, the last step will always distribute the remaining balance, ensuring the contract is fully drained by the end of the distribution.

- **Extensibility:**
  The contract is abstract and designed to be inherited. The inheriting contract is responsible for calling the internal functions at the appropriate times and for handling the actual transfer of rewards.

- **Gas Efficiency:**
  The distribution state is packed into a single storage slot.

## **Example Usage Pattern**

```solidity
function claimReward() external {
    uint256 reward = calculateDistributableReward();
    require(reward > 0, "No reward available");

    // Transfer reward to user (implement in inheriting contract)
    _sendReward(msg.sender, reward);

    // Move to next step
    advanceDistributionStep();
}
```
