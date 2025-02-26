/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {console} from "forge-std/src/console.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IHarvester} from "src/interfaces/IHarvester.sol";
import {StorageMasks} from "src/libraries/StorageMasks.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Accountant - Reward Distribution and Accounting System
/// @notice A comprehensive system for managing reward distribution and accounting across vaults and users.
/// @dev Implements a gas-optimized packed storage system for efficient reward tracking and distribution.
///      Key responsibilities:
///      - Tracks user balances and rewards across vaults.
///      - Manages protocol fees and dynamic harvest fees.
///      - Handles reward distribution and claiming.
///      - Maintains integral calculations for reward accrual.
contract Accountant is ReentrancyGuardTransient, Ownable2Step {
    using Math for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- STORAGE STRUCTURES
    //////////////////////////////////////////////////////

    /// @notice Packed vault data structure into 2 slots for gas optimization and safety.
    /// @dev supplyAndIntegralSlot: [supply (128) | integral (128)].
    /// @dev pendingRewards: [fee subject amount (128) | total amount (128)].
    struct PackedVault {
        uint256 supplyAndIntegralSlot; // slot1 -> supplyAndIntegralSlot
        uint256 pendingRewardsSlot; // slot2 -> pendingRewards
    }

    /// @notice Packed account data structure into 2 slots for gas optimization and safety.
    /// @dev balanceAndIntegralSlot: [balance (128) | integral (128)].
    /// @dev pendingRewards: direct storage of pending rewards.
    struct PackedAccount {
        uint256 balanceAndIntegralSlot; // slot1 -> balanceAndIntegralSlot
        uint256 pendingRewards; // direct storage of pending rewards
    }

    /// @notice Packed fees data structure into 1 slot for gas optimization.
    /// @dev feesSlot: [totalFeePercent (64) | protocolFeePercent (64) | harvestFeePercent (64)].
    /// @dev All fees are capped at MAX_FEE_PERCENT (0.4e18) which fits in 64 bits.
    struct PackedFees {
        uint256 feesSlot;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Scaling factor used for fixed-point arithmetic precision (1e18).
    uint256 public constant SCALING_FACTOR = 1e27;

    /// @notice The maximum fee percent (40%).
    uint256 public constant MAX_FEE_PERCENT = 0.4e18;

    /// @notice The minimum amount of rewards to be added to the vault.
    uint256 public constant MIN_MEANINGFUL_REWARDS = 1e18;

    /// @notice The registry of addresses.
    address public immutable PROTOCOL_CONTROLLER;

    /// @notice The reward token.
    address public immutable REWARD_TOKEN;

    /// @notice The protocol ID.
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The default protocol fee.
    /// @dev The validity of this value is not checked. It must always be valid
    uint256 internal constant DEFAULT_PROTOCOL_FEE = 0.15e18;

    /// @notice The default harvest fee.
    /// @dev The validity of this value is not checked. It must always be valid
    uint256 internal constant DEFAULT_HARVEST_FEE = 0.005e18;

    //////////////////////////////////////////////////////
    /// --- STATE VARIABLES
    //////////////////////////////////////////////////////

    /// @notice The fees.
    PackedFees public fees;

    /// @notice The balance threshold for harvest fee calculation.
    /// @dev If set to 0, maximum harvest fee always applies.
    uint256 public HARVEST_URGENCY_THRESHOLD;

    /// @notice The total protocol fees collected but not yet claimed.
    uint256 public protocolFeesAccrued;

    /// @notice Supply of vaults.
    /// @dev Vault address -> PackedVault.
    mapping(address vault => PackedVault vaultData) private vaults;

    /// @notice Balances of accounts per vault.
    /// @dev Vault address -> Account address -> PackedAccount.
    mapping(address vault => mapping(address account => PackedAccount accountData)) private accounts;

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error thrown when the caller is not a vault.
    error OnlyVault();

    /// @notice Error thrown when the caller is not allowed.
    error OnlyAllowed();

    /// @notice Error thrown when the harvester is not set.
    error NoHarvester();

    /// @notice Error thrown when the fee receiver is not set.
    error NoFeeReceiver();

    /// @notice Error thrown when there are no pending rewards.
    error NoPendingRewards();

    /// @notice Error thrown when a fee exceeds the maximum allowed
    error FeeExceedsMaximum();

    /// @notice Error thrown when harvest data length doesn't match vaults length
    error InvalidHarvestDataLength();

    /// @notice Error thrown when harvest fee would exceed protocol fee
    error HarvestFeeExceedsProtocolFee();

    /// @notice Error thrown when the protocol controller is invalid
    error InvalidProtocolController();

    /// @notice Error thrown when the reward token is invalid
    error InvalidRewardToken();

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////

    /// @notice Emitted when protocol fees are claimed.
    event ProtocolFeesClaimed(uint256 amount);

    /// @notice Emitted when a vault harvests rewards.
    event Harvest(address indexed vault, uint256 amount);

    /// @notice Emitted when the protocol fee percent is updated.
    event ProtocolFeePercentSet(uint256 oldProtocolFeePercent, uint256 newProtocolFeePercent);

    /// @notice Emitted when the balance threshold is updated.
    event HarvestUrgencyThresholdSet(uint256 oldThreshold, uint256 newThreshold);

    /// @notice Emitted when the harvest fee percent is updated.
    event HarvestFeePercentSet(uint256 oldHarvestFeePercent, uint256 newHarvestFeePercent);

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    modifier onlyAllowed() {
        require(IProtocolController(PROTOCOL_CONTROLLER).allowed(address(this), msg.sender, msg.sig), OnlyAllowed());
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the Accountant contract with owner, registry, and reward token.
    /// @param _owner The address of the contract owner.
    /// @param _registry The address of the registry contract.
    /// @param _rewardToken The address of the reward token.
    /// @custom:throws OwnableInvalidOwner If the owner is the zero address.
    /// @custom:throws InvalidProtocolController If the protocol controller is the zero address.
    /// @custom:throws InvalidRewardToken If the reward token is the zero address.
    constructor(address _owner, address _registry, address _rewardToken) Ownable(_owner) {
        require(_registry != address(0), InvalidProtocolController());
        require(_rewardToken != address(0), InvalidRewardToken());

        /// set the immutable variables
        PROTOCOL_CONTROLLER = _registry;
        REWARD_TOKEN = _rewardToken;

        /// set the initial fees to the default values, and emit the update events
        fees.feesSlot = _calculateFeesSlot(DEFAULT_PROTOCOL_FEE, DEFAULT_HARVEST_FEE);
        emit HarvestFeePercentSet(0, DEFAULT_HARVEST_FEE);
        emit ProtocolFeePercentSet(0, DEFAULT_PROTOCOL_FEE);
    }

    //////////////////////////////////////////////////////
    /// --- CHECKPOINT OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Checkpoints the state of the vault on every account action.
    /// @dev Handles four types of operations:
    ///      1. Minting (from = address(0)): Creates new tokens.
    ///      2. Burning (to = address(0)): Destroys tokens.
    ///      3. Transfers: Updates balances and rewards for both sender and receiver.
    ///      4. Reward Distribution: Processes pending rewards if any exist.
    /// @param asset The underlying asset address of the vault.
    /// @param from The source address (address(0) for minting).
    /// @param to The destination address (address(0) for burning).
    /// @param amount The amount of tokens being transferred/minted/burned.
    /// @param pendingRewards New rewards to be distributed to the vault.
    /// @param harvested Whether these rewards were already harvested by the vault and sent to the contract.
    /// @custom:throws OnlyVault If caller is not the registered vault for the asset.
    function checkpoint(
        address asset,
        address from,
        address to,
        uint256 amount,
        IStrategy.PendingRewards memory pendingRewards,
        bool harvested
    ) external nonReentrant {
        require(IProtocolController(PROTOCOL_CONTROLLER).vaults(asset) == msg.sender, OnlyVault());

        PackedVault storage _vault = vaults[msg.sender];
        uint256 vaultSupplyAndIntegral = _vault.supplyAndIntegralSlot;
        uint256 pendingRewardsSlot = _vault.pendingRewardsSlot;

        uint256 supply = vaultSupplyAndIntegral & StorageMasks.SUPPLY;
        uint256 integral = (vaultSupplyAndIntegral & StorageMasks.INTEGRAL) >> 128;

        // Process any pending rewards if they exist and there is supply
        if (pendingRewards.totalAmount > 0 && supply > 0) {
            /// Unpack pending rewards.
            uint256 feeSubjectAmount = pendingRewardsSlot & StorageMasks.PENDING_REWARDS_FEE_SUBJECT;
            uint256 totalAmount = (pendingRewardsSlot & StorageMasks.PENDING_REWARDS_TOTAL) >> 128;

            // Calculate the new rewards to be added to the vault.

            uint256 newRewards = pendingRewards.totalAmount - totalAmount;
            uint256 newFeeSubjectAmount = pendingRewards.feeSubjectAmount - feeSubjectAmount;

            uint256 totalFees;
            if (harvested && newRewards > 0) {
                // Calculate total fees in one operation
                // We charge only protocol fee on the harvested rewards.
                if (newFeeSubjectAmount > 0) {
                    totalFees = newFeeSubjectAmount.mulDiv(getProtocolFeePercent(), 1e18);

                    // Update protocol fees accrued.
                    protocolFeesAccrued += totalFees;
                }

                // Update integral with new rewards per token
                integral += (newRewards - totalFees).mulDiv(SCALING_FACTOR, supply);
            }
            // If the new rewards are above the minimum meaningful rewards,
            // we update the integral and pending rewards.
            // Otherwise, we don't update the integral to avoid precision loss. It won't be lost, just delayed.
            else if (newRewards >= MIN_MEANINGFUL_REWARDS) {
                // Calculate total fees in one operation
                // We charge protocol and harvest fees on the unclaimed rewards.
                if (newFeeSubjectAmount > 0) {
                    totalFees = newFeeSubjectAmount.mulDiv(getProtocolFeePercent(), 1e18);
                }

                // Get harvest fee for the unclaimed rewards.
                totalFees += newRewards.mulDiv(getHarvestFeePercent(), 1e18);

                // Update integral with new rewards per token
                integral += (newRewards - totalFees).mulDiv(SCALING_FACTOR, supply);

                // Update pending rewards slot.
                // Properly pack the fee subject amount and total amount according to their bit positions
                _vault.pendingRewardsSlot = ((pendingRewards.totalAmount << 128) & StorageMasks.PENDING_REWARDS_TOTAL)
                    | pendingRewards.feeSubjectAmount;
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
                isDecrease: true,
                currentIntegral: integral
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
                isDecrease: false,
                currentIntegral: integral
            });
        }

        // Update vault storage with new supply and integral
        _vault.supplyAndIntegralSlot = (supply & StorageMasks.SUPPLY) | ((integral << 128) & StorageMasks.INTEGRAL);
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
        uint256 amount,
        bool isDecrease,
        uint256 currentIntegral
    ) private {
        PackedAccount storage _account = accounts[vault][account];
        uint256 accountBalanceAndIntegral = _account.balanceAndIntegralSlot;

        uint256 balance = accountBalanceAndIntegral & StorageMasks.BALANCE;
        uint256 accountIntegral = (accountBalanceAndIntegral & StorageMasks.ACCOUNT_INTEGRAL) >> 128;

        // Update pending rewards based on the integral difference.
        _account.pendingRewards += (currentIntegral - accountIntegral).mulDiv(balance, SCALING_FACTOR);

        // Update balance
        balance = isDecrease ? balance - amount : balance + amount;

        // Pack and store updated values
        _account.balanceAndIntegralSlot =
            (balance & StorageMasks.BALANCE) | ((currentIntegral << 128) & StorageMasks.ACCOUNT_INTEGRAL);
    }

    /// @notice Returns the total supply of tokens in a vault.
    /// @param vault The vault address to query.
    /// @return The total supply of tokens in the vault.
    function totalSupply(address vault) external view returns (uint256) {
        return vaults[vault].supplyAndIntegralSlot & StorageMasks.SUPPLY;
    }

    /// @notice Returns the token balance of an account in a vault.
    /// @param vault The vault address to query.
    /// @param account The account address to check.
    /// @return The account's token balance in the vault.
    function balanceOf(address vault, address account) external view returns (uint256) {
        return accounts[vault][account].balanceAndIntegralSlot & StorageMasks.BALANCE;
    }

    /// @notice Returns the pending rewards for an account in a vault.
    /// @param vault The vault address to query.
    /// @param account The account address to check.
    /// @return The pending rewards for the account in the vault.
    function getPendingRewards(address vault, address account) external view returns (uint256) {
        return accounts[vault][account].pendingRewards;
    }

    /// @notice Returns the pending rewards for a vault.
    /// @param vault The vault address to query.
    /// @return The pending rewards for the vault.
    function getPendingRewards(address vault) external view returns (uint256) {
        return (vaults[vault].pendingRewardsSlot & StorageMasks.PENDING_REWARDS_TOTAL) >> 128;
    }

    //////////////////////////////////////////////////////
    /// --- HARVEST OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Harvests rewards from multiple vaults.
    /// @param _vaults Array of vault addresses to harvest from.
    /// @param _harvestData Array of harvest data for each vault.
    /// @custom:throws NoHarvester If the harvester is not set.
    function harvest(address[] calldata _vaults, bytes[] calldata _harvestData) external nonReentrant {
        require(_vaults.length == _harvestData.length, InvalidHarvestDataLength());
        _batchHarvest({_vaults: _vaults, harvestData: _harvestData, receiver: msg.sender});
    }

    /// @dev Internal implementation of batch harvesting.
    /// @param _vaults Array of vault addresses to harvest from.
    /// @param harvestData Harvest data for each vault.
    function _batchHarvest(address[] calldata _vaults, bytes[] calldata harvestData, address receiver) internal {
        // Cache registry to avoid multiple SLOADs
        address registry = PROTOCOL_CONTROLLER;
        address harvester = IProtocolController(registry).harvester(PROTOCOL_ID);
        require(harvester != address(0), NoHarvester());

        uint256 totalHarvesterFee;

        for (uint256 i; i < _vaults.length; i++) {
            /// Harvest the vault and increment total harvester fee.
            totalHarvesterFee +=
                _harvest({vault: _vaults[i], harvestData: harvestData[i], harvester: harvester, registry: registry});
        }

        // Transfer total harvester fee if any
        if (totalHarvesterFee > 0) {
            IERC20(REWARD_TOKEN).safeTransfer(receiver, totalHarvesterFee);
        }
    }

    /// @dev Internal implementation of single vault harvesting.
    /// @return harvesterFee The harvester fee for this harvest operation.
    function _harvest(address vault, bytes calldata harvestData, address harvester, address registry)
        private
        returns (uint256 harvesterFee)
    {
        // Fees should be calculated before the harvest.
        uint256 currentHarvestFee = getCurrentHarvestFee();
        uint256 protocolFeePercent = getProtocolFeePercent();

        // Harvest the asset
        (uint256 feeSubjectAmount, uint256 totalAmount) = abi.decode(
            harvester.functionDelegateCall(
                abi.encodeWithSelector(
                    IHarvester.harvest.selector, IProtocolController(registry).assets(vault), harvestData
                )
            ),
            (uint256, uint256)
        );
        if (totalAmount == 0) return 0;

        /// We charge protocol fee on the feeable amount.
        uint256 protocolFee = feeSubjectAmount.mulDiv(protocolFeePercent, 1e18);

        /// Update protocol fees accrued.
        protocolFeesAccrued += protocolFee;

        /// We charge harvester fee on the total amount.
        harvesterFee = totalAmount.mulDiv(currentHarvestFee, 1e18);

        PackedVault storage _vault = vaults[vault];
        uint256 pendingRewardsSlot = _vault.pendingRewardsSlot;
        uint256 pendingRewards = (pendingRewardsSlot & StorageMasks.PENDING_REWARDS_TOTAL) >> 128;

        /// Refund the excess harvest fee taken at the checkpoint.
        if (pendingRewards > 0 && currentHarvestFee < getHarvestFeePercent()) {
            totalAmount += pendingRewards.mulDiv(getHarvestFeePercent() - currentHarvestFee, 1e18);
        }

        // Update vault state
        _updateVaultState({vault: _vault, pendingRewards: pendingRewards, amount: totalAmount});

        /// Always clear pending rewards after harvesting.
        _vault.pendingRewardsSlot = 0;

        emit Harvest(vault, totalAmount);
    }

    /// @dev Updates vault state during harvest.
    /// @param vault The vault address to update.
    /// @param pendingRewards Previous pending rewards to be cleared
    /// @param amount The total reward amount.
    //// TODO: Should I add netDelta to protocolFeesAccrued for simplicity?
    function _updateVaultState(PackedVault storage vault, uint256 pendingRewards, uint256 amount) private {
        // Early return if no state changes needed
        if (pendingRewards == 0 || amount == pendingRewards) return;

        // netDelta is defined as newRewards + refund - totalFees.
        // Since amount = newRewards + pendingRewards + refund,
        // netDelta = amount - pendingRewards.
        uint256 netDelta = amount - pendingRewards;

        /// Unpack supply and integral.
        uint256 supply = vault.supplyAndIntegralSlot & StorageMasks.SUPPLY;
        uint256 integral = (vault.supplyAndIntegralSlot & StorageMasks.INTEGRAL) >> 128;

        // Only update the integral if the net extra rewards are positive.
        integral += (uint256(netDelta).mulDiv(SCALING_FACTOR, supply));

        /// Update vault storage.
        vault.supplyAndIntegralSlot = (supply & StorageMasks.SUPPLY) | ((integral << 128) & StorageMasks.INTEGRAL);
    }

    /// @notice Returns the current harvest fee based on contract balance
    /// @return The current harvest fee percentage
    function getCurrentHarvestFee() public view returns (uint256) {
        uint256 threshold = HARVEST_URGENCY_THRESHOLD;
        // If threshold is 0, always return max harvest fee
        if (threshold == 0) return getHarvestFeePercent();

        uint256 balance = IERC20(REWARD_TOKEN).balanceOf(address(this));
        return balance >= threshold ? 0 : getHarvestFeePercent() * (threshold - balance) / threshold;
    }

    /// @notice Returns the current harvest fee percentage.
    /// @return The harvest fee percentage.
    function getHarvestFeePercent() public view returns (uint256) {
        return fees.feesSlot & StorageMasks.HARVEST_FEE;
    }

    /// @notice Updates the harvest fee percentage.
    /// @param _harvestFeePercent New harvest fee percentage (scaled by 1e18).
    /// @custom:throws FeeExceedsMaximum If fee would exceed maximum.
    function setHarvestFeePercent(uint256 _harvestFeePercent) external onlyOwner {
        uint256 feeSlot = fees.feesSlot;
        uint256 protocolFeePercent = (feeSlot & StorageMasks.PROTOCOL_FEE) >> 64;
        uint256 oldHarvestFeePercent = feeSlot & StorageMasks.HARVEST_FEE;

        uint256 totalFee = protocolFeePercent + _harvestFeePercent;
        require(totalFee <= MAX_FEE_PERCENT, FeeExceedsMaximum());

        /// Harvest fee must be less than protocol fee.
        /// @dev This is to prevent the _updateVaultState from taking more fees than the protocol fee
        /// and break the netDelta invariant.
        require(_harvestFeePercent < protocolFeePercent, HarvestFeeExceedsProtocolFee());

        fees.feesSlot = _calculateFeesSlot(protocolFeePercent, _harvestFeePercent);

        emit HarvestFeePercentSet(oldHarvestFeePercent, _harvestFeePercent);
    }

    /// @notice Updates the balance threshold for harvest fee calculation
    /// @param _threshold New balance threshold. Set to 0 to always apply maximum harvest fee.
    function setHarvestUrgencyThreshold(uint256 _threshold) external onlyOwner {
        emit HarvestUrgencyThresholdSet(HARVEST_URGENCY_THRESHOLD, _threshold);
        HARVEST_URGENCY_THRESHOLD = _threshold;
    }

    //////////////////////////////////////////////////////
    /// --- CLAIM OPERATIONS
    //////////////////////////////////////////////////////

    /// @notice Claims rewards from multiple vaults for the caller.
    /// @param _vaults Array of vault addresses to claim rewards from.
    /// @param receiver Address that will receive the claimed rewards.
    /// @param harvestData Optional harvest data for each vault. Empty bytes for vaults that don't need harvesting.
    /// @custom:throws NoPendingRewards If there are no rewards to claim.
    function claim(address[] calldata _vaults, address receiver, bytes[] calldata harvestData) external nonReentrant {
        /// If receiver is not set, use the caller as the receiver.
        receiver = receiver == address(0) ? msg.sender : receiver;

        require(harvestData.length == 0 || harvestData.length == _vaults.length, InvalidHarvestDataLength());

        if (harvestData.length != 0) {
            _batchHarvest({_vaults: _vaults, harvestData: harvestData, receiver: receiver});
        }

        _claim({_vaults: _vaults, account: msg.sender, receiver: receiver});
    }

    /// @notice Claims rewards on behalf of an account.
    /// @param _vaults Array of vault addresses to claim rewards from.
    /// @param account Address to claim rewards for.
    /// @param receiver Address that will receive the claimed rewards.
    /// @param harvestData Optional harvest data for each vault. Empty bytes for vaults that don't need harvesting.
    /// @custom:throws OnlyAllowed If caller is not allowed to claim on behalf of others.
    /// @custom:throws NoPendingRewards If there are no rewards to claim.
    function claim(address[] calldata _vaults, address account, address receiver, bytes[] calldata harvestData)
        external
        onlyAllowed
        nonReentrant
    {
        /// If receiver is not set, use the account as the receiver.
        receiver = receiver == address(0) ? account : receiver;

        require(harvestData.length == 0 || harvestData.length == _vaults.length, InvalidHarvestDataLength());

        if (harvestData.length != 0) {
            _batchHarvest({_vaults: _vaults, harvestData: harvestData, receiver: receiver});
        }
        _claim({_vaults: _vaults, account: account, receiver: receiver});
    }

    /// @dev Internal implementation of claim functionality.
    /// @param _vaults Array of vault addresses to claim rewards from.
    /// @param account Address to claim rewards for.
    /// @param receiver Address that will receive the claimed rewards.
    /// @custom:throws NoPendingRewards If the total claimed amount is zero.
    function _claim(address[] calldata _vaults, address account, address receiver) internal {
        uint256 totalAmount;
        uint256 vaultsLength = _vaults.length;

        // Process each vault
        for (uint256 i; i < vaultsLength; i++) {
            PackedVault storage vault = vaults[_vaults[i]];
            PackedAccount storage userAccount = accounts[_vaults[i]][account];

            // Load all storage values at once
            uint256 accountData = userAccount.balanceAndIntegralSlot;
            uint256 balance = accountData & StorageMasks.BALANCE;

            // Skip if user has no balance and no pending rewards
            if (balance != 0 || userAccount.pendingRewards != 0) {
                uint256 vaultData = vault.supplyAndIntegralSlot;
                uint256 accountIntegral = (accountData & StorageMasks.ACCOUNT_INTEGRAL) >> 128;
                uint256 vaultIntegral = (vaultData & StorageMasks.INTEGRAL) >> 128;

                // Calculate new rewards if integral has increased
                if (vaultIntegral > accountIntegral) {
                    totalAmount += (vaultIntegral - accountIntegral) * balance / SCALING_FACTOR;
                }
                // Add any pending rewards
                totalAmount += userAccount.pendingRewards;

                // Update account storage with new integral and reset pending rewards
                userAccount.balanceAndIntegralSlot =
                    (balance & StorageMasks.BALANCE) | ((vaultIntegral << 128) & StorageMasks.ACCOUNT_INTEGRAL);
                userAccount.pendingRewards = 0;
            }
        }

        require(totalAmount != 0, NoPendingRewards());
        // Transfer accumulated rewards to receiver
        IERC20(REWARD_TOKEN).safeTransfer(receiver, totalAmount);
    }

    //////////////////////////////////////////////////////
    /// --- FEE MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Returns the current protocol fee percentage.
    /// @return The protocol fee percentage.
    function getProtocolFeePercent() public view returns (uint256) {
        return (fees.feesSlot & StorageMasks.PROTOCOL_FEE) >> 64;
    }

    /// @notice Returns the total fee percentage (protocol + harvest).
    /// @return The total fee percentage.
    function getTotalFeePercent() public view returns (uint256) {
        return (fees.feesSlot & StorageMasks.TOTAL_FEE) >> 128;
    }

    /// @notice Updates the protocol fee percentage.
    /// @param _protocolFeePercent New protocol fee percentage (scaled by 1e18).
    /// @custom:throws FeeExceedsMaximum If fee would exceed maximum.
    function setProtocolFeePercent(uint256 _protocolFeePercent) external onlyOwner {
        require(_protocolFeePercent <= MAX_FEE_PERCENT, FeeExceedsMaximum());

        uint256 feeSlot = fees.feesSlot;
        uint256 oldProtocolFeePercent = (feeSlot & StorageMasks.PROTOCOL_FEE) >> 64;
        uint256 harvestFeePercent = feeSlot & StorageMasks.HARVEST_FEE;

        uint256 totalFee = _protocolFeePercent + harvestFeePercent;
        require(totalFee <= MAX_FEE_PERCENT, FeeExceedsMaximum());

        fees.feesSlot = _calculateFeesSlot(_protocolFeePercent, harvestFeePercent);

        emit ProtocolFeePercentSet(oldProtocolFeePercent, _protocolFeePercent);
    }

    /// @notice Claims accumulated protocol fees.
    /// @dev Transfers fees to the configured fee receiver.
    /// @custom:throws NoFeeReceiver If the fee receiver is not set.
    function claimProtocolFees() external nonReentrant {
        address feeReceiver = IProtocolController(PROTOCOL_CONTROLLER).feeReceiver(PROTOCOL_ID);
        require(feeReceiver != address(0), NoFeeReceiver());

        IERC20(REWARD_TOKEN).transfer(feeReceiver, protocolFeesAccrued);

        emit ProtocolFeesClaimed(protocolFeesAccrued);

        protocolFeesAccrued = 0;
    }

    /// @notice Calculates the fees slot.
    /// @param _protocolFee The protocol fee.
    /// @param _harvestFee The harvest fee.
    /// @return The calculatedfees slot.
    function _calculateFeesSlot(uint256 _protocolFee, uint256 _harvestFee) internal pure returns (uint256) {
        return ((_protocolFee + _harvestFee) << 128) | (_protocolFee << 64) | _harvestFee;
    }
}
