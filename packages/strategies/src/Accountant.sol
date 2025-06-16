// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title Accountant - Reward Distribution and Accounting System
/// @notice Central accounting system that tracks user balances and distributes rewards across all vaults
/// @dev Uses integral-based accounting for gas-efficient reward distribution:
///      - Rewards are tracked as integrals (cumulative reward per token)
///      - User rewards = (current integral - last user integral) * user balance
///      Two reward distribution policies:
///      - HARVEST: Claims rewards from gauge on every user action (higher gas, immediate rewards)
///      - CHECKPOINT: Accumulates rewards in gauge until manual harvest, but users can claim 
///                   from the shared reward pool if tokens are available (cross-vault liquidity)
contract Accountant is ReentrancyGuardTransient, Ownable2Step, IAccountant {
    using Math for uint256;
    using Math for uint128;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    // --- STORAGE STRUCTURES
    //////////////////////////////////////////////////////

    /// @notice Tracks reward and supply data for each vault
    /// @dev Packed struct to minimize storage costs (3 storage slots)
    struct VaultData {
        uint256 integral;           // Cumulative reward per token (scaled by SCALING_FACTOR)
        uint128 supply;             // Total supply of vault tokens
        uint128 feeSubjectAmount;   // Amount of rewards subject to fees
        uint128 totalAmount;        // Total reward amount including fee-exempt rewards
        uint128 netCredited;        // Net rewards already credited to users (after fees)
        uint128 reservedHarvestFee; // Harvest fees reserved but not yet paid out
        uint128 reservedProtocolFee;// Protocol fees reserved but not yet accrued
    }

    /// @notice Tracks individual user positions within a vault
    /// @dev Integral tracking enables O(1) reward calculations
    struct AccountData {
        uint128 balance;            // User's token balance in the vault
        uint256 integral;           // Last integral value when user's rewards were updated
        uint256 pendingRewards;     // Rewards earned but not yet claimed
    }

    /// @notice Struct that defines the fees parameters.
    struct FeesParams {
        uint128 protocolFeePercent;
        uint128 harvestFeePercent;
    }

    //////////////////////////////////////////////////////
    // --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Precision multiplier for integral calculations (1e27 for maximum precision)
    /// @dev Higher precision prevents rounding errors in reward distribution
    uint128 public constant SCALING_FACTOR = 1e27;

    /// @notice Maximum combined fee percentage to protect users (40%)
    uint128 public constant MAX_FEE_PERCENT = 0.4e18;

    /// @notice Minimum rewards threshold to update integrals in CHECKPOINT mode
    /// @dev Prevents precision loss from tiny reward amounts
    uint128 public constant MIN_MEANINGFUL_REWARDS = 1e18;

    /// @notice Central registry for protocol components
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    /// @notice The reward token distributed by this accountant (e.g., CRV)
    address public immutable REWARD_TOKEN;

    /// @notice Protocol identifier this accountant manages
    bytes4 public immutable PROTOCOL_ID;

    /// @notice Default protocol fee charged on rewards (15%)
    uint128 internal constant DEFAULT_PROTOCOL_FEE = 0.15e18;

    /// @notice Default harvest fee paid to harvesters (0.1%)
    /// @dev Compensates for gas costs when calling harvest() function
    uint128 internal constant DEFAULT_HARVEST_FEE = 0.001e18;

    //////////////////////////////////////////////////////
    // --- STATE VARIABLES
    //////////////////////////////////////////////////////

    /// @notice The feesParams struct.
    FeesParams public feesParams;

    /// @notice The total protocol fees collected but not yet claimed.
    uint256 public protocolFeesAccrued;

    /// @notice Supply of vaults.
    /// @dev Vault address -> VaultData.
    mapping(address vault => VaultData vaultData) public vaults;

    /// @notice Balances of accounts per vault.
    /// @dev Vault address -> Account address -> AccountData.
    mapping(address vault => mapping(address account => AccountData accountData)) public accounts;

    //////////////////////////////////////////////////////
    // --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the caller is not a vault.
    error OnlyVault();

    /// @notice Error thrown when the caller is not allowed.
    error OnlyAllowed();

    /// @notice Error thrown when the strategy is not set.
    error NoStrategy();

    /// @notice Error thrown when the fee receiver is not set.
    error NoFeeReceiver();

    /// @notice Error thrown when there are no pending rewards.
    error NoPendingRewards();

    /// @notice Error thrown when the pending rewards are not enough.
    error InsufficientPendingRewards();

    /// @notice Error thrown when the net credits are not enough.
    error NetCreditsNotEnough();

    /// @notice Error thrown when the fees exceed the rewards.
    error FeesExceedRewards();

    /// @notice Error thrown when a fee exceeds the maximum allowed
    error FeeExceedsMaximum();

    /// @notice Error thrown when the vault is invalid
    error InvalidVault();

    /// @notice Error thrown when harvest data length doesn't match vaults length
    error InvalidHarvestDataLength();

    /// @notice Error thrown when the protocol controller is invalid
    error InvalidProtocolController();

    /// @notice Error thrown when the reward token is invalid
    error InvalidRewardToken();

    /// @notice Error thrown when the protocol ID is invalid
    error InvalidProtocolId();

    /// @notice Error thrown when the harvester has not transferred the correct amount of tokens to the Accountant contract
    error HarvestTokenNotReceived();

    //////////////////////////////////////////////////////
    // --- EVENTS
    //////////////////////////////////////////////////////

    /// @notice Emitted when protocol fees are claimed.
    event ProtocolFeesClaimed(uint256 amount);

    /// @notice Emitted when a vault harvests rewards.
    event Harvest(
        address indexed vault,
        uint256 integral,
        uint256 supply,
        uint256 amount,
        uint256 protocolFee,
        uint256 harvesterFee
    );

    /// @notice Emitted when a checkpoint is made.
    event Checkpoint(
        address indexed vault,
        address indexed from,
        address indexed to,
        uint128 amount,
        uint256 integral,
        uint256 supply,
        IStrategy.HarvestPolicy policy
    );

    /// @notice Emitted when an account checkpoint is made.
    event AccountCheckpoint(
        address indexed vault, address indexed account, uint128 balance, uint256 integral, uint256 pendingRewards
    );

    /// @notice Emitted when a user claims rewards.
    event RewardsClaimed(address indexed vault, address indexed account, address receiver, uint256 amount);

    /// @notice Emitted when the protocol fee percent is updated.
    event ProtocolFeePercentSet(uint128 oldProtocolFeePercent, uint128 newProtocolFeePercent);

    /// @notice Emitted when the harvest fee percent is updated.
    event HarvestFeePercentSet(uint128 oldHarvestFeePercent, uint128 newHarvestFeePercent);

    /// @notice Emitted when a deposit is made via a referrer
    /// @param referrer The address of the referrer
    /// @param referree The address of the referree (the address that receives the shares)
    /// @param assets The amount of assets deposited (1:1 with shares)
    event Referrer(address indexed referrer, address referree, uint128 assets);

    //////////////////////////////////////////////////////
    // --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Restricts access to addresses with specific function permissions
    /// @dev Used for harvest() and other privileged operations
    modifier onlyAllowed() {
        require(PROTOCOL_CONTROLLER.allowed(address(this), msg.sender, msg.sig), OnlyAllowed());
        _;
    }

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the Accountant contract with owner, registry, and reward token.
    /// @param _owner The address of the contract owner.
    /// @param _registry The address of the registry contract.
    /// @param _rewardToken The address of the reward token.
    /// @param _protocolId The bytes4 ID of the protocol
    /// @custom:throws OwnableInvalidOwner If the owner is the zero address.
    /// @custom:throws InvalidProtocolController If the protocol controller is the zero address.
    /// @custom:throws InvalidRewardToken If the reward token is the zero address.
    constructor(address _owner, address _registry, address _rewardToken, bytes4 _protocolId) Ownable(_owner) {
        require(_registry != address(0), InvalidProtocolController());
        require(_rewardToken != address(0), InvalidRewardToken());
        require(_protocolId != bytes4(0), InvalidProtocolId());

        /// set the immutable variables
        PROTOCOL_CONTROLLER = IProtocolController(_registry);
        REWARD_TOKEN = _rewardToken;
        PROTOCOL_ID = _protocolId;

        /// set the initial fees to the default values, and emit the update events
        feesParams = FeesParams({protocolFeePercent: DEFAULT_PROTOCOL_FEE, harvestFeePercent: DEFAULT_HARVEST_FEE});
        emit HarvestFeePercentSet(0, DEFAULT_HARVEST_FEE);
        emit ProtocolFeePercentSet(0, DEFAULT_PROTOCOL_FEE);
    }

    //////////////////////////////////////////////////////
    // --- CHECKPOINT OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Updates user balances and distributes rewards on every vault action
    /// @dev Core accounting function called by vaults during transfers, mints, and burns
    ///      
    ///      Token Operations:
    ///      - Mint (from = 0): Increases supply, updates receiver's reward integral
    ///      - Burn (to = 0): Decreases supply, updates sender's reward integral  
    ///      - Transfer: Updates both sender and receiver integrals
    ///
    ///      Reward Distribution Policies:
    ///      - HARVEST: Claims rewards on every action, only protocol fee charged
    ///      - CHECKPOINT: Accumulates rewards until harvest(), both fees charged
    ///        In CHECKPOINT, fees are reserved (not immediately accrued) to ensure
    ///        the harvester receives proper compensation when they eventually harvest
    /// @param gauge The underlying gauge address of the vault.
    /// @param from The source address (address(0) for minting).
    /// @param to The destination address (address(0) for burning).
    /// @param amount The amount of tokens being transferred/minted/burned.
    /// @param pendingRewards New rewards to be distributed to the vault.
    /// @param policy The harvest policy to use.
    /// @custom:throws OnlyVault If caller is not the registered vault for the gauge.
    function checkpoint(
        address gauge,
        address from,
        address to,
        uint128 amount,
        IStrategy.PendingRewards calldata pendingRewards,
        IStrategy.HarvestPolicy policy
    ) public nonReentrant {
        require(PROTOCOL_CONTROLLER.vaults(gauge) == msg.sender, OnlyVault());

        VaultData storage _vault = vaults[msg.sender];
        uint128 supply = _vault.supply;
        uint256 integral = _vault.integral;

        // Process any pending rewards if they exist and there is supply
        if (pendingRewards.totalAmount > 0 && supply > 0) {
            // Calculate the new rewards to be added to the vault.
            uint128 newRewards = pendingRewards.totalAmount - _vault.totalAmount;
            uint128 newFeeSubjectAmount = pendingRewards.feeSubjectAmount - _vault.feeSubjectAmount;

            /// @dev Guard against fees exceeding the rewards.
            require(pendingRewards.feeSubjectAmount <= pendingRewards.totalAmount, FeesExceedRewards());

            uint128 totalFees;
            if (policy == IStrategy.HarvestPolicy.HARVEST && newRewards > 0) {
                // Calculate total fees in one operation
                // We charge only protocol fee on the harvested rewards.
                if (newFeeSubjectAmount > 0) {
                    totalFees = newFeeSubjectAmount.mulDiv(getProtocolFeePercent(), 1e18).toUint128();
                    // Update protocol fees accrued.
                    protocolFeesAccrued += totalFees;
                }

                // Update integral with new rewards per token
                integral += (newRewards - totalFees).mulDiv(SCALING_FACTOR, supply);
            }
            // If the new rewards are above the minimum meaningful rewards,
            // we update the integral and pending rewards.
            // Otherwise, we don't update the integral to avoid precision loss. It won't be lost, just delayed.
            else if (policy == IStrategy.HarvestPolicy.CHECKPOINT && newRewards >= MIN_MEANINGFUL_REWARDS) {
                // Calculate total fees in one operation
                // We charge protocol and harvest fees on the unclaimed rewards.
                if (newFeeSubjectAmount > 0) {
                    totalFees = newFeeSubjectAmount.mulDiv(getProtocolFeePercent(), 1e18).toUint128();

                    _vault.reservedProtocolFee += totalFees;
                }

                // Get harvest fee for the unclaimed rewards.
                uint128 harvestFee = newRewards.mulDiv(getHarvestFeePercent(), 1e18).toUint128();

                // The net rewards we are *actually crediting* now
                uint128 netIncrement = newRewards - totalFees - harvestFee;

                // Update integral with new rewards per token
                integral += netIncrement.mulDiv(SCALING_FACTOR, supply);

                // Record how many total net rewards we've credited so far
                _vault.netCredited += netIncrement;

                // Record the harvest fee for the unclaimed rewards
                _vault.reservedHarvestFee += harvestFee;

                // Update the total amount and the fee subject amount of the Vault
                _vault.totalAmount = pendingRewards.totalAmount;

                // Update the fee subject amount of the Vault
                _vault.feeSubjectAmount = pendingRewards.feeSubjectAmount;
            }
        }

        // Handle token operations
        if (from == address(0)) {
            // Minting operation
            supply += amount;
        } else {
            // Update sender's balance and rewards
            _updateAccountState({
                vault: msg.sender,
                account: from,
                amount: amount,
                currentIntegral: integral,
                isDecrease: true
            });
        }

        if (to == address(0)) {
            // Burning operation
            supply -= amount;
        } else {
            // Update receiver's balance and rewards
            _updateAccountState({
                vault: msg.sender,
                account: to,
                amount: amount,
                currentIntegral: integral,
                isDecrease: false
            });
        }

        // Update vault data with new supply and integral
        _vault.integral = integral;
        _vault.supply = supply;

        emit Checkpoint(msg.sender, from, to, amount, integral, supply, policy);
    }

    /// @notice Checkpoints the state of the vault on every account action.
    /// @dev This function is a wrapper of `checkpoint` that emits the `Referrer` event.
    /// @param gauge The underlying gauge address of the vault.
    /// @param from The source address (address(0) for minting).
    /// @param to The destination address (address(0) for burning).
    /// @param amount The amount of tokens being transferred/minted/burned.
    /// @param pendingRewards New rewards to be distributed to the vault.
    /// @param policy The harvest policy to use.
    /// @param referrer The address of the referrer.
    /// @custom:throws OnlyVault If caller is not the registered vault for the gauge.
    function checkpoint(
        address gauge,
        address from,
        address to,
        uint128 amount,
        IStrategy.PendingRewards calldata pendingRewards,
        IStrategy.HarvestPolicy policy,
        address referrer
    ) external {
        // call the checkpoint function as normal (the function check if the caller is the authorized vault)
        checkpoint(gauge, from, to, amount, pendingRewards, policy);

        // emit the referrer deposit event if the referrer is set
        if (referrer != address(0)) emit Referrer(referrer, to, amount);
    }

    /// @dev Updates account state during operations.
    /// @param vault The vault address.
    /// @param account The account to update.
    /// @param amount The amount to add/subtract.
    /// @param isDecrease Whether to decrease (true) or increase (false) the balance.
    /// @param currentIntegral The current reward integral to checkpoint against.
    function _updateAccountState(
        address vault,
        address account,
        uint128 amount,
        bool isDecrease,
        uint256 currentIntegral
    ) private {
        AccountData storage accountData = accounts[vault][account];
        // cache the balance in the stack for gas optimization
        uint128 accountBalance = accountData.balance;

        // Update pending rewards based on the integral difference.
        accountData.pendingRewards +=
            (currentIntegral - accountData.integral).mulDiv(uint256(accountBalance), SCALING_FACTOR);
        accountData.balance = isDecrease ? accountBalance - amount : accountBalance + amount;
        accountData.integral = currentIntegral;

        // Emit the account checkpoint event
        emit AccountCheckpoint(vault, account, accountData.balance, currentIntegral, accountData.pendingRewards);
    }

    /// @notice Returns the total supply of tokens in a vault.
    /// @param vault The vault address to query.
    /// @return _ The total supply of tokens in the vault.
    function totalSupply(address vault) external view returns (uint128) {
        return vaults[vault].supply;
    }

    /// @notice Returns the token balance of an account in a vault.
    /// @param vault The vault address to query.
    /// @param account The account address to check.
    /// @return _ The account's token balance in the vault.
    function balanceOf(address vault, address account) external view returns (uint128) {
        return accounts[vault][account].balance;
    }

    /// @notice Returns the pending rewards for a vault.
    /// @param vault The vault address to query.
    /// @return The pending rewards for the vault.
    function getPendingRewards(address vault) external view returns (uint128) {
        return vaults[vault].totalAmount;
    }

    /// @notice Returns the pending rewards for an account in a vault.
    /// @param vault The vault address to query.
    /// @param account The account address to check.
    /// @return _ The pending rewards for the account in the vault.
    function getPendingRewards(address vault, address account) external view returns (uint256) {
        return accounts[vault][account].pendingRewards;
    }

    //////////////////////////////////////////////////////
    // --- HARVEST OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Harvests rewards from multiple gauges and distributes them to vaults
    /// @dev Called by harvesters to claim rewards from external protocols and update integrals
    /// @param _gauges Array of gauges to harvest from
    /// @param _harvestData Protocol-specific data for harvesting each gauge
    /// @param _receiver Address that will receive the harvest fee as compensation
    /// @custom:throws InvalidHarvestDataLength If array lengths don't match
    function harvest(address[] calldata _gauges, bytes[] calldata _harvestData, address _receiver) external {
        require(_gauges.length == _harvestData.length, InvalidHarvestDataLength());
        _harvest(_gauges, _harvestData, _receiver);
    }

    /// @dev Batch harvests rewards and updates vault integrals
    /// @dev Gas optimizations:
    ///      1. Single strategy.flush() call at the end for all rewards
    ///      2. One token transfer for all harvested rewards
    ///      3. Defers rewards using transient storage during harvest
    function _harvest(address[] memory _gauges, bytes[] memory harvestData, address receiver) internal nonReentrant {
        // Cache strategy to avoid multiple SLOADs
        address strategy = PROTOCOL_CONTROLLER.strategy(PROTOCOL_ID);
        require(strategy != address(0), NoStrategy());

        // Fetch the balance of the Accountant contract before harvesting.
        uint256 balanceBefore = IERC20(REWARD_TOKEN).balanceOf(address(this));

        uint256 totalHarvesterFee;
        uint256 totalRewardsAmount;
        // First pass: harvest all gauges and update vault states
        for (uint256 i; i < _gauges.length; i++) {
            address gauge = _gauges[i];
            address vault = PROTOCOL_CONTROLLER.vaults(gauge);
            require(vault != address(0), InvalidVault());

            VaultData storage _vault = vaults[vault];

            // 1. Pull rewards from the strategy
            IStrategy.PendingRewards memory pendingRewards = IStrategy(strategy).harvest(gauge, harvestData[i]);

            // 2. Under‑delivery guard (totals must cover soft credits)
            require(
                pendingRewards.totalAmount >= _vault.totalAmount
                    && pendingRewards.feeSubjectAmount >= _vault.feeSubjectAmount,
                InsufficientPendingRewards()
            );

            /// @dev Guard against fees exceeding the rewards.
            require(pendingRewards.feeSubjectAmount <= pendingRewards.totalAmount, FeesExceedRewards());

            // Skip if strategy reports zero
            if (pendingRewards.totalAmount == 0) continue;
            // 3. Aggregate global rewards
            totalRewardsAmount += pendingRewards.totalAmount;

            // 4. Start accounting
            uint256 protocolFee = _vault.reservedProtocolFee;
            uint256 harvesterFee = _vault.reservedHarvestFee;
            uint256 netCredited = _vault.netCredited;

            // Strategy must at least make LPs whole
            uint256 netAfterReservedFees = pendingRewards.totalAmount - protocolFee - harvesterFee;
            require(netAfterReservedFees >= netCredited, NetCreditsNotEnough());

            if (netAfterReservedFees > netCredited && _vault.supply > 0) {
                uint256 newRewards = netAfterReservedFees - netCredited;

                /// Take the fee from the net delta
                uint256 newHarvesterFee = newRewards.mulDiv(getHarvestFeePercent(), 1e18);
                /// Update the harvester fee
                harvesterFee += newHarvesterFee;

                if (pendingRewards.feeSubjectAmount > _vault.feeSubjectAmount) {
                    uint256 newFeeSubjectAmount = pendingRewards.feeSubjectAmount - _vault.feeSubjectAmount;
                    uint256 newProtocolFee = newFeeSubjectAmount.mulDiv(getProtocolFeePercent(), 1e18);

                    protocolFee += newProtocolFee;

                    // Adjust newRewards to account for protocol fee
                    newRewards -= newProtocolFee;
                }

                // Add only that delta to the integral
                _vault.integral += (newRewards - newHarvesterFee).mulDiv(SCALING_FACTOR, _vault.supply);
            }

            /// Update the total harvester fee
            totalHarvesterFee += harvesterFee;

            /// Update the total protocol fee
            protocolFeesAccrued += protocolFee;

            _vault.netCredited = 0; // fully settled thanks to the guard
            _vault.totalAmount = 0;
            _vault.feeSubjectAmount = 0;
            _vault.reservedHarvestFee = 0;
            _vault.reservedProtocolFee = 0;

            emit Harvest(vault, _vault.integral, _vault.supply, pendingRewards.totalAmount, protocolFee, harvesterFee);
        }

        // If no valid harvests, return early
        if (totalRewardsAmount == 0) return;

        // Flush all accumulated rewards at once
        IStrategy(strategy).flush();

        // Check that the strategy has transferred the correct amount of reward tokens to this contract
        require(
            IERC20(REWARD_TOKEN).balanceOf(address(this)) >= balanceBefore + totalRewardsAmount,
            HarvestTokenNotReceived()
        );

        // Transfer total harvester fee if any
        if (totalHarvesterFee > 0) {
            IERC20(REWARD_TOKEN).safeTransfer(receiver, totalHarvesterFee);
        }
    }

    /// @notice Returns the current harvest fee percentage.
    /// @return _ The harvest fee percentage.
    function getHarvestFeePercent() public view returns (uint128) {
        return feesParams.harvestFeePercent;
    }

    /// @notice Updates the harvest fee percentage.
    /// @param newHarvestFeePercent New harvest fee percentage (scaled by 1e18).
    /// @custom:throws FeeExceedsMaximum If fee would exceed maximum.
    function setHarvestFeePercent(uint128 newHarvestFeePercent) external onlyOwner {
        FeesParams storage currentFees = feesParams;

        // check that the new total fee (protocol + harvest) is valid
        uint256 totalFee = uint256(currentFees.protocolFeePercent) + uint256(newHarvestFeePercent);
        require(totalFee <= MAX_FEE_PERCENT, FeeExceedsMaximum());

        // emit the harvest event before updating the storage pointer
        emit HarvestFeePercentSet(currentFees.harvestFeePercent, newHarvestFeePercent);

        // set the new protocol fee percent
        feesParams.harvestFeePercent = newHarvestFeePercent;
    }

    //////////////////////////////////////////////////////
    // --- CLAIM OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Claims rewards from multiple vaults for the caller
    /// @dev In CHECKPOINT mode, can claim if rewards are available in the contract
    /// @param _gauges Array of gauges to claim rewards from
    /// @param harvestData Optional: triggers harvest before claim if provided
    /// @custom:throws NoPendingRewards If there are no rewards to claim
    function claim(address[] calldata _gauges, bytes[] calldata harvestData) external {
        claim(_gauges, harvestData, msg.sender);
    }

    /// @notice Claims rewards and sends to a specific receiver
    /// @dev Optionally harvests first if harvestData is provided
    /// @param _gauges Array of gauges to claim rewards from
    /// @param harvestData Optional harvest data (empty array to skip harvest)
    /// @param receiver Address that will receive the claimed rewards
    /// @custom:throws NoPendingRewards If there are no rewards to claim
    function claim(address[] calldata _gauges, bytes[] calldata harvestData, address receiver) public {
        require(harvestData.length == 0 || harvestData.length == _gauges.length, InvalidHarvestDataLength());

        if (harvestData.length != 0) {
            _harvest(_gauges, harvestData, receiver);
        }

        _claim({_gauges: _gauges, account: msg.sender, receiver: receiver});
    }

    /// @notice Claims multiple vault rewards on behalf of an account.
    /// @param _gauges Array of gauges to claim rewards from.
    /// @param account Address to claim rewards for.
    /// @param harvestData Optional harvest data for each gauge. Empty bytes for gauges that don't need harvesting.
    /// @dev expected to be called by authorized accounts only
    /// @custom:throws OnlyAllowed If caller is not allowed to claim on behalf of others.
    /// @custom:throws NoPendingRewards If there are no rewards to claim.
    function claim(address[] calldata _gauges, address account, bytes[] calldata harvestData) external {
        claim(_gauges, account, harvestData, account);
    }

    /// @notice Claims multiple vault rewards on behalf of an account and sends them to a specific address.
    /// @param _gauges Array of gauges to claim rewards from.
    /// @param account Address to claim rewards for.
    /// @param harvestData Optional harvest data for each gauge. Empty bytes for gauges that don't need harvesting.
    /// @param receiver Address that will receive the claimed rewards.
    /// @dev expected to be called by authorized accounts only
    /// @custom:throws OnlyAllowed If caller is not allowed to claim on behalf of others.
    /// @custom:throws NoPendingRewards If there are no rewards to claim.
    function claim(address[] calldata _gauges, address account, bytes[] calldata harvestData, address receiver)
        public
        onlyAllowed
    {
        require(harvestData.length == 0 || harvestData.length == _gauges.length, InvalidHarvestDataLength());

        if (harvestData.length != 0) {
            _harvest(_gauges, harvestData, receiver);
        }

        _claim({_gauges: _gauges, account: account, receiver: receiver});
    }

    /// @dev Internal implementation of claim functionality.
    /// @param _gauges Array of gauges to claim rewards from.
    /// @param account Address to claim rewards for.
    /// @param receiver Address that will receive the claimed rewards.
    /// @custom:throws NoPendingRewards If the total claimed amount is zero.
    function _claim(address[] calldata _gauges, address account, address receiver) internal nonReentrant {
        uint256 totalAmount;

        address vault;
        // For each gauge, check if the account has any rewards to claim
        for (uint256 i; i < _gauges.length; i++) {
            vault = PROTOCOL_CONTROLLER.vaults(_gauges[i]);
            require(vault != address(0), InvalidVault());

            // Get the account data for this gauge
            AccountData storage accountData = accounts[vault][account];

            // Get the current balance for this vault
            uint128 balance = accountData.balance;

            // If account has any rewards to claim for this vault, calculate the amount. Otherwise, skip.
            if (balance != 0 || accountData.pendingRewards != 0) {
                // Get vault's and account's integral
                uint256 accountIntegral = accountData.integral;
                uint256 vaultIntegral = vaults[vault].integral;

                // If vault's integral is higher than account's integral, calculate the rewards and update the total.
                uint256 claimableAmount = accountData.pendingRewards;
                if (vaultIntegral > accountIntegral) {
                    claimableAmount += (vaultIntegral - accountIntegral).mulDiv(balance, SCALING_FACTOR);
                }

                // In any case, add the pending rewards to the total amount
                totalAmount += claimableAmount;

                // Update account's integral with the current value of Vault's integral
                accountData.integral = vaultIntegral;

                // reset the stored pending rewards for this vault
                accountData.pendingRewards = 0;

                // Emit the account checkpoint event
                emit AccountCheckpoint(vault, account, balance, vaultIntegral, 0);

                // Emit the claim event
                emit RewardsClaimed(vault, account, receiver, claimableAmount);
            }
        }

        // If there is no amount to claim for any vault, revert.
        require(totalAmount != 0, NoPendingRewards());

        // Transfer accumulated rewards to the receiver
        IERC20(REWARD_TOKEN).safeTransfer(receiver, totalAmount);
    }

    //////////////////////////////////////////////////////
    // --- FEE MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Returns the current protocol fee percentage.
    /// @return _ The protocol fee percentage.
    function getProtocolFeePercent() public view returns (uint128) {
        return feesParams.protocolFeePercent;
    }

    /// @notice Updates the protocol fee percentage.
    /// @param newProtocolFeePercent New protocol fee percentage (scaled by 1e18).
    /// @custom:throws FeeExceedsMaximum If fee would exceed maximum.
    function setProtocolFeePercent(uint128 newProtocolFeePercent) external onlyOwner {
        FeesParams storage currentFees = feesParams;

        // check that the total fee (protocol + harvest) is valid
        uint128 totalFee = newProtocolFeePercent + currentFees.harvestFeePercent;
        require(totalFee <= MAX_FEE_PERCENT, FeeExceedsMaximum());

        // emit the update event
        emit ProtocolFeePercentSet(currentFees.protocolFeePercent, newProtocolFeePercent);

        // set the new protocol fee percent
        currentFees.protocolFeePercent = newProtocolFeePercent;
    }

    /// @notice Claims accumulated protocol fees.
    /// @dev Transfers fees to the configured fee receiver.
    /// @custom:throws NoFeeReceiver If the fee receiver is not set.
    function claimProtocolFees() external nonReentrant {
        // get the fee receiver from the protocol controller and check that it is valid
        address feeReceiver = PROTOCOL_CONTROLLER.feeReceiver(PROTOCOL_ID);
        require(feeReceiver != address(0), NoFeeReceiver());

        // get the protocol fees accrued until now and reset the stored value
        uint256 currentAccruedProtocolFees = protocolFeesAccrued;
        protocolFeesAccrued = 0;

        // transfer the accrued protocol fees to the fee receiver and emit the claim event
        IERC20(REWARD_TOKEN).safeTransfer(feeReceiver, currentAccruedProtocolFees);
        emit ProtocolFeesClaimed(currentAccruedProtocolFees);
    }

    /// @notice Returns the total fee percentage (protocol + harvest).
    /// @return _ The total fee percentage.
    function getTotalFeePercent() external view returns (uint128) {
        return feesParams.protocolFeePercent + feesParams.harvestFeePercent;
    }
}
