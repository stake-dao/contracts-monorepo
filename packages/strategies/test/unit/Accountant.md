# Test Scenarios for the Accountant Contract

## 1. Deployment and Configuration
- Deploy with initial fee values. Confirm protocol fee of 15% and harvest fee of 0.5%, totaling 15.5%.
- Update protocol and harvest fees, ensuring they do not exceed 40% and that harvest < protocol. Check for event emissions.

## 2. Checkpoint
### 2a. Simple Mint and Burn
- Call `checkpoint` on mint (from `address(0)` to user). Confirm supply increases.
- Call `checkpoint` on burn (from user to `address(0)`). Confirm supply decreases.
- Verify the integral and pending rewards remain correct.

### 2b. Transfer Between Two Users
- User A has a balance; User B has none.
- Transfer from A to B and call `checkpoint`.
- Confirm A’s balance decreases and B’s increases. Check new rewards for both. Ensure no net loss or gain.

### 2c. With Pending Rewards
- Trigger pending rewards and pass them to `checkpoint`.
- Confirm the vault’s integral updates and fees if supply > 0.
- If supply = 0, verify no revert.

### 2d. Edge Cases
- `pendingRewards` with zero supply. Confirm no revert.
- Mint after a large integral. The new user starts at the current integral without unearned rewards.
- Transfer the entire balance from a user. Confirm the departing user’s pending updates and the recipient’s balance.

## 3. Fee-Based Reward Distribution
- Use a mock vault with tokens. Send harvestable rewards, then call `checkpoint` with the pending amount.
- Confirm `protocolFeesAccrued` increments. Check user balances remain unchanged until claim.
- Vary reward sizes to check rounding correctness.

## 4. Harvest Process
- Harvest multiple vaults with zero or nonzero rewards.
- Verify the aggregator logic sums fees properly.
- If `HARVEST_URGENCY_THRESHOLD` is 0, confirm the harvest fee always remains at its max.
- If a threshold is set, deposit enough tokens to exceed it. Confirm the harvest fee reduces accordingly.

## 5. Claiming
- Mint vault tokens for two users. Accumulate rewards and claim partially.
- Confirm new integrals and cleared pending rewards.
- If no rewards are pending, confirm `NoPendingRewards` revert.
- Claim from multiple vaults with varying rewards.

## 6. Protocol Fee Management
- Confirm `protocolFeesAccrued` updates after each harvest.
- Confirm `claimProtocolFees` transfers fees to the fee receiver.
- Revert if the fee receiver is unset.

## 7. Access Control
- Attempt disallowed calls, such as unauthorized claims on others’ behalf. Confirm revert.
- Check `OnlyVault` triggers when a non-vault calls `checkpoint`.
- Check `OnlyAllowed` triggers for restricted calls.