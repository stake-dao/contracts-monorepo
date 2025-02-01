/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IHarvester} from "src/interfaces/IHarvester.sol";
import {StorageMasks} from "src/libraries/StorageMasks.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Accountant - Reward distribution and accounting system
/// @notice Manages the distribution of rewards across vaults and users
/// @dev Handles reward accounting, fee collection, and donation tracking with gas-optimized packed storage
/// @dev Key responsibilities:
/// - Tracks user balances and rewards across vaults
/// - Manages protocol fees, harvest fees, and donation premiums
/// - Handles reward distribution and claiming
/// - Maintains integral calculations for reward accrual
contract Accountant is ReentrancyGuardTransient, Ownable2Step {
    using Math for uint256;
    using Address for address;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice Packed vault data structure into 1 slot for gas optimization
    /// @dev supplyAndIntegralAndPendingRewardsSlot: [supply (96) | integral (96) | pendingRewards (64)]
    struct PackedVault {
        uint256 supplyAndIntegralAndPendingRewardsSlot; // slot1 -> supplyAndIntegralAndPendingRewardsSlot
    }

    /// @notice Packed account data structure into 1 slot for gas optimization
    /// @dev balanceAndRewardsSlot: [balance (96) | integral (96) | pendingRewards (64)]
    struct PackedAccount {
        uint256 balanceAndRewardsSlot; // slot -> balanceAndRewardsSlot
    }

    /// @notice Packed donation data structure into 1 slot for gas optimization
    /// @dev donationAndIntegralTimestampSlot: [donation (96) | integral (96) | timestamp (40) | premiumPercent (24)]
    struct PackedDonation {
        uint256 donationAndIntegralTimestampSlot; // slot -> donationAndIntegralTimestampSlot
    }

    /// @notice Packed fees and premiums data structure into 1 slot for gas optimization
    /// @dev feesSlot: [harvestFeePercent (64) | donationPremiumPercent (64) | protocolFeePercent (64)]
    struct PackedFees {
        uint256 feesSlot;
    }

    /// @notice Scaling factor used for fixed-point arithmetic precision (1e18)
    uint256 public constant SCALING_FACTOR = 1e18;

    /// @notice The maximum fee percent (40%)
    uint256 public constant MAX_FEE_PERCENT = 0.4e18;

    /// @notice The registry of addresses
    address public immutable REGISTRY;

    /// @notice The reward token
    address public immutable REWARD_TOKEN;

    /// @notice The fees and premiums
    PackedFees public fees;

    /// @notice The total protocol fees collected but not yet claimed
    uint256 public protocolFeesAccrued;

    /// @notice The global pending rewards of all vaults
    uint96 public globalPendingRewards;

    /// @notice The global harvest integral of all vaults
    uint96 public globalHarvestIntegral;

    /// @notice Supply of vaults
    /// @dev Vault address -> PackedVault
    mapping(address vault => PackedVault vaultData) private vaults;

    /// @notice Donations of accounts
    mapping(address account => PackedDonation donationData) private donations;

    /// @notice Balances of accounts per vault
    /// @dev Vault address -> Account address -> PackedAccount
    mapping(address vault => mapping(address account => PackedAccount accountData)) private accounts;

    /// @notice Error thrown when the caller is not allowed
    error OnlyAllowed();

    /// @notice Error thrown when the caller is not a vault
    error OnlyVault();

    /// @notice Error thrown when the donation claim is too soon
    error TooSoon();

    /// @notice Error thrown when there is no donation
    error NoDonation();

    /// @notice Error thrown when the harvester is not set
    error NoHarvester();

    /// @notice Error thrown when the fee receiver is not set
    error NoFeeReceiver();

    /// @notice Error thrown when there are no pending rewards
    error NoPendingRewards();

    /// @notice Error thrown when the input is invalid
    error WhatWrongWithYou();

    /// @notice Error thrown when there is nothing to harvest
    error NothingToHarvest();

    /// @notice Error thrown when the harvest integral is not reached
    error HarvestIntegralNotReached();

    /// @notice Emitted when protocol fees are claimed
    event ProtocolFeesClaimed(uint256 amount);

    /// @notice Emitted when a vault harvests rewards
    event Harvest(address indexed vault, uint256 amount);

    /// @notice Emitted when an account donates
    event Donation(address indexed donator, uint256 amount);

    /// @notice Emitted when an account claims rewards
    event ClaimDonation(address indexed account, uint256 amount);

    /// @notice Emitted when the harvest fee percent is updated
    event HarvestFeePercentSet(uint256 oldHarvestFeePercent, uint256 newHarvestFeePercent);

    /// @notice Emitted when the donation fee percent is updated
    event DonationFeePercentSet(uint256 oldDonationFeePercent, uint256 newDonationFeePercent);

    /// @notice Emitted when the protocol fee percent is updated
    event ProtocolFeePercentSet(uint256 oldProtocolFeePercent, uint256 newProtocolFeePercent);

    modifier onlyAllowed() {
        require(IRegistry(REGISTRY).allowed(msg.sender, msg.sig), OnlyAllowed());
        _;
    }

    constructor(address _owner, address _registry, address _rewardToken) Ownable(_owner) {
        REGISTRY = _registry;
        REWARD_TOKEN = _rewardToken;

        /// Fees are set to 0.5% for harvest, 0.5% for donation, and 15% for protocol.
        fees.feesSlot = (0.005e18 << 64) | (0.005e18 << 96) | (0.15e18 << 128);
    }

    /// @notice Checkpoints the state of the vault on every account action
    /// @dev Handles four types of operations:
    ///      1. Minting (from = address(0)): Creates new tokens
    ///      2. Burning (to = address(0)): Destroys tokens
    ///      3. Transfers: Updates balances and rewards for both sender and receiver
    ///      4. Reward Distribution: Processes pending rewards if any exist
    /// @param asset The underlying asset address of the vault
    /// @param from The source address (address(0) for minting)
    /// @param to The destination address (address(0) for burning)
    /// @param amount The amount of tokens being transferred/minted/burned
    /// @param pendingRewards New rewards to be distributed to the vault
    /// @param claimed Whether these rewards were already claimed
    /// @custom:throws OnlyVault If caller is not the registered vault for the asset
    function checkpoint(address asset, address from, address to, uint256 amount, uint256 pendingRewards, bool claimed)
        external
        nonReentrant
    {
        // Validate caller is the registered vault for this asset
        require(IRegistry(REGISTRY).vaults(asset) == msg.sender, OnlyVault());

        PackedVault storage _vault = vaults[msg.sender];
        uint256 vaultSupplyAndIntegral = _vault.supplyAndIntegralAndPendingRewardsSlot;

        uint256 supply = vaultSupplyAndIntegral & StorageMasks.SUPPLY_MASK;
        uint256 integral = (vaultSupplyAndIntegral & StorageMasks.INTEGRAL_MASK) >> 96;

        // Process any pending rewards if they exist and there is supply
        if (pendingRewards > 0 && supply > 0) {
            if (!claimed) {
                // Only update global pending rewards for unclaimed rewards
                globalPendingRewards += pendingRewards.toUint96();
            }

            (uint256 harvestFeePercent, uint256 donationPremiumPercent, uint256 protocolFeePercent) = _loadFees();

            // Calculate and deduct fees
            uint256 totalFees =
                pendingRewards.mulDiv(harvestFeePercent + donationPremiumPercent + protocolFeePercent, 1e18);
            pendingRewards -= totalFees;

            // Update integral with new rewards per token
            integral += pendingRewards.mulDiv(SCALING_FACTOR, supply).toUint96();
        }

        // Handle token operations
        if (from == address(0)) {
            // Minting operation
            supply += amount;
        } else {
            // Update sender's balance and rewards
            _updateAccountState(msg.sender, from, amount, true, integral);
        }

        if (to == address(0)) {
            // Burning operation
            supply -= amount;
        } else {
            // Update receiver's balance and rewards
            _updateAccountState(msg.sender, to, amount, false, integral);
        }

        // Update vault storage with new supply and integral
        _vault.supplyAndIntegralAndPendingRewardsSlot = (supply & StorageMasks.SUPPLY_MASK)
            | ((integral << 96) & StorageMasks.INTEGRAL_MASK)
            | ((pendingRewards << 192) & StorageMasks.PENDING_REWARDS_MASK);
    }

    /// @dev Updates an account's balance and rewards
    /// @param vault The vault address
    /// @param account The account to update
    /// @param amount The amount to add/subtract
    /// @param isDecrease Whether to decrease (true) or increase (false) the balance
    /// @param currentIntegral The current reward integral to checkpoint against
    function _updateAccountState(
        address vault,
        address account,
        uint256 amount,
        bool isDecrease,
        uint256 currentIntegral
    ) private {
        PackedAccount storage _account = accounts[vault][account];
        uint256 accountBalanceAndRewards = _account.balanceAndRewardsSlot;

        uint256 balance = accountBalanceAndRewards & StorageMasks.BALANCE_MASK;
        uint256 accountIntegral = (accountBalanceAndRewards & StorageMasks.ACCOUNT_INTEGRAL_MASK) >> 96;
        uint256 accountPendingRewards = (accountBalanceAndRewards & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK) >> 192;

        // Update pending rewards based on the integral difference
        accountPendingRewards += (currentIntegral - accountIntegral).mulDiv(balance, SCALING_FACTOR).toUint64();

        // Update balance
        balance = isDecrease ? balance - amount : balance + amount;

        // Pack and store updated values
        _account.balanceAndRewardsSlot = (balance & StorageMasks.BALANCE_MASK)
            | ((currentIntegral << 96) & StorageMasks.ACCOUNT_INTEGRAL_MASK)
            | ((accountPendingRewards << 192) & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK);
    }

    /// @notice Claims rewards from multiple vaults for the caller
    /// @param _vaults Array of vault addresses to claim rewards from
    /// @param receiver Address that will receive the claimed rewards
    /// @custom:throws NoPendingRewards If there are no rewards to claim
    function claim(address[] calldata _vaults, address receiver) external nonReentrant {
        _claim(_vaults, msg.sender, receiver);
    }

    /// @notice Claims rewards on behalf of an account (restricted to allowed callers)
    /// @param _vaults Array of vault addresses to claim rewards from
    /// @param account Address to claim rewards for
    /// @param receiver Address that will receive the claimed rewards
    /// @custom:throws OnlyAllowed If caller is not allowed to claim on behalf of others
    /// @custom:throws NoPendingRewards If there are no rewards to claim
    function claim(address[] calldata _vaults, address account, address receiver) external onlyAllowed nonReentrant {
        _claim(_vaults, account, receiver);
    }

    /// @dev Internal implementation of the claim functionality
    /// @param _vaults Array of vault addresses to claim rewards from
    /// @param account Address to claim rewards for
    /// @param receiver Address that will receive the claimed rewards
    /// @custom:throws NoPendingRewards If the total claimed amount is zero
    function _claim(address[] calldata _vaults, address account, address receiver) internal {
        uint256 amount = 0;
        address vault;

        // Storage for unpacking vault and account data
        uint256 vaultSupplyAndIntegral;
        uint256 integral;
        uint256 balance;
        uint256 accountIntegral;
        uint256 accountPendingRewards;
        uint256 accountBalanceAndRewards;

        // Process each vault
        uint256 vaultsLength = _vaults.length;
        for (uint256 i; i < vaultsLength; i++) {
            vault = _vaults[i];

            // Load storage references
            PackedVault storage _vault = vaults[vault];
            PackedAccount storage _account = accounts[vault][account];

            // Unpack vault data
            vaultSupplyAndIntegral = _vault.supplyAndIntegralAndPendingRewardsSlot;
            integral = (vaultSupplyAndIntegral & StorageMasks.INTEGRAL_MASK) >> 96;

            // Unpack account data
            accountBalanceAndRewards = _account.balanceAndRewardsSlot;
            balance = accountBalanceAndRewards & StorageMasks.BALANCE_MASK;
            accountIntegral = (accountBalanceAndRewards & StorageMasks.ACCOUNT_INTEGRAL_MASK) >> 96;
            accountPendingRewards = (accountBalanceAndRewards & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK) >> 192;

            // Add new rewards if integral has increased
            if (integral > accountIntegral) {
                amount += (integral - accountIntegral).mulDiv(balance, SCALING_FACTOR);
            }

            // Add any pending rewards
            amount += accountPendingRewards;

            // Update account storage with new integral and reset pending rewards
            _account.balanceAndRewardsSlot = (balance & StorageMasks.BALANCE_MASK)
                | ((integral << 96) & StorageMasks.ACCOUNT_INTEGRAL_MASK)
                | ((0 << 192) & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK);
        }

        // Revert if no rewards to claim
        if (amount == 0) revert NoPendingRewards();

        // Transfer accumulated rewards to receiver
        IERC20(REWARD_TOKEN).safeTransfer(receiver, amount);
    }

    /// @notice Harvests rewards from a vault
    /// @param vault The address of the vault to harvest rewards from
    /// @param extraData Additional data required for the harvest operation
    /// @custom:throws NoHarvester If the harvester is not set
    /// @custom:throws NothingToHarvest If no rewards are available to harvest
    function harvest(address vault, bytes calldata extraData) external nonReentrant {
        // Cache REGISTRY to avoid multiple SLOADs
        address registry = REGISTRY;
        address harvester = IRegistry(registry).HARVESTER();
        require(harvester != address(0), NoHarvester());

        // Harvest the asset
        uint256 amount = abi.decode(
            harvester.functionDelegateCall(
                abi.encodeWithSelector(IHarvester.harvest.selector, IRegistry(registry).assets(vault), extraData)
            ),
            (uint256)
        );
        require(amount != 0, NothingToHarvest());

        // Calculate fees
        {
            (uint256 harvestFeePercent, uint256 donationPremiumPercent, uint256 protocolFeePercent) = _loadFees();
            uint256 protocolFee = amount.mulDiv(protocolFeePercent, 1e18);
            uint256 harvesterFee = amount.mulDiv(harvestFeePercent, 1e18);
            uint256 donationPremium = amount.mulDiv(donationPremiumPercent, 1e18);

            // Update protocol fees
            protocolFeesAccrued += protocolFee;

            // Transfer harvester fee
            IERC20(REWARD_TOKEN).safeTransfer(msg.sender, harvesterFee);

            // Update vault state
            _updateVaultState(vault, amount, protocolFee + harvesterFee + donationPremium);
        }

        emit Harvest(vault, amount);
    }

    /// @dev Updates vault state during harvest
    /// @param vault The vault address to update
    /// @param amount The total reward amount
    /// @param totalFees The total fees to deduct
    function _updateVaultState(address vault, uint256 amount, uint256 totalFees) private {
        PackedVault storage _vault = vaults[vault];
        uint256 slot = _vault.supplyAndIntegralAndPendingRewardsSlot;
        uint256 supply = slot & StorageMasks.SUPPLY_MASK;
        uint256 integral = (slot & StorageMasks.INTEGRAL_MASK) >> 96;
        uint256 pendingRewards = (slot & StorageMasks.PENDING_REWARDS_MASK) >> 192;

        // Update global harvest integral with pre-fee amount
        globalHarvestIntegral += amount.mulDiv(SCALING_FACTOR, supply).toUint96();

        // Update amount after deducting all fees
        amount -= (totalFees + pendingRewards);

        // Update vault integral with post-fee amount
        integral += amount.mulDiv(SCALING_FACTOR, supply).toUint96();

        // Update vault storage
        _vault.supplyAndIntegralAndPendingRewardsSlot = (supply & StorageMasks.SUPPLY_MASK)
            | ((integral << 96) & StorageMasks.INTEGRAL_MASK) | ((0 << 192) & StorageMasks.PENDING_REWARDS_MASK);
    }

    /// @notice Allows users to donate their pending rewards
    /// @dev Records donation with current harvest integral for later claiming with premium
    /// @custom:throws NoPendingRewards If there are no global pending rewards
    function donate() external nonReentrant {
        require(globalPendingRewards != 0, NoPendingRewards());

        // Transfer pending rewards from donor
        IERC20(REWARD_TOKEN).safeTransferFrom(msg.sender, address(this), globalPendingRewards);

        // Update donation storage
        PackedDonation storage _donation = donations[msg.sender];
        uint256 donationAndIntegralTimestamp = _donation.donationAndIntegralTimestampSlot;

        // Add to existing donation amount
        uint256 donation = donationAndIntegralTimestamp & StorageMasks.DONATION_MASK;
        donation += globalPendingRewards;

        // Store donation with current harvest integral
        _donation.donationAndIntegralTimestampSlot = (donation & StorageMasks.DONATION_MASK)
            | ((globalHarvestIntegral << 96) & StorageMasks.DONATION_INTEGRAL_MASK)
            | ((block.timestamp << 192) & StorageMasks.DONATION_TIMESTAMP_MASK)
            | ((getDonationPremiumPercent() << 232) & StorageMasks.DONATION_PREMIUM_PERCENT_MASK);

        emit Donation(msg.sender, globalPendingRewards);

        // Reset global pending rewards
        globalPendingRewards = 0;
    }

    /// @notice Allows users to claim back their donations plus earned premium
    /// @dev Verifies harvest integral has been reached and calculates total claimable amount
    /// @custom:throws HarvestIntegralNotReached If global harvest integral is less than donation integral
    /// @custom:throws NoDonation If the user has no donation to claim
    /// @custom:throws TooSoon If claiming before minimum time period
    function claimDonation() external nonReentrant {
        PackedDonation storage _donation = donations[msg.sender];
        uint256 donationAndIntegralTimestamp = _donation.donationAndIntegralTimestampSlot;

        // Verify donation is not too soon
        uint256 timestamp = (donationAndIntegralTimestamp & StorageMasks.DONATION_TIMESTAMP_MASK) >> 192;
        require(timestamp + 1 days <= block.timestamp, TooSoon());

        // Verify harvest integral has been reached
        uint256 integral = (donationAndIntegralTimestamp & StorageMasks.DONATION_INTEGRAL_MASK) >> 96;
        require(globalHarvestIntegral >= integral, HarvestIntegralNotReached());

        // Verify donation exists
        uint256 donation = donationAndIntegralTimestamp & StorageMasks.DONATION_MASK;
        require(donation != 0, NoDonation());

        // Get donation premium percent
        uint256 donationPremiumPercent =
            (donationAndIntegralTimestamp & StorageMasks.DONATION_PREMIUM_PERCENT_MASK) >> 232;

        // Calculate total claimable amount including premium
        uint256 totalClaimable = donation + donation.mulDiv(donationPremiumPercent, 1e18);

        // Transfer total amount to donor
        IERC20(REWARD_TOKEN).safeTransfer(msg.sender, totalClaimable);

        // Reset donation while preserving latest harvest integral
        _donation.donationAndIntegralTimestampSlot = (0 & StorageMasks.DONATION_MASK)
            | ((globalHarvestIntegral << 96) & StorageMasks.DONATION_INTEGRAL_MASK)
            | ((block.timestamp << 192) & StorageMasks.DONATION_TIMESTAMP_MASK);

        emit ClaimDonation(msg.sender, totalClaimable);
    }

    /// @notice Returns the total supply of tokens in a vault
    /// @param vault The vault address to query
    /// @return The total supply of tokens in the vault
    function totalSupply(address vault) external view returns (uint256) {
        return vaults[vault].supplyAndIntegralAndPendingRewardsSlot & StorageMasks.SUPPLY_MASK;
    }

    /// @notice Calculates the claimable donation amount including premium
    /// @param account The account to check donation for
    /// @return donation The total claimable amount (original + premium)
    function getDonation(address account) external view returns (uint256 donation) {
        uint256 donationAndIntegralTimestamp = donations[account].donationAndIntegralTimestampSlot;

        // Get original donation amount
        donation = donationAndIntegralTimestamp & StorageMasks.DONATION_MASK;

        // Get donation premium percent
        uint256 donationPremiumPercent =
            (donationAndIntegralTimestamp & StorageMasks.DONATION_PREMIUM_PERCENT_MASK) >> 232;

        // Add premium
        donation += donation.mulDiv(donationPremiumPercent, 1e18);
    }

    /// @notice Returns the token balance of an account in a vault
    /// @param vault The vault address to query
    /// @param account The account address to check
    /// @return The account's token balance in the vault
    function balanceOf(address vault, address account) external view returns (uint256) {
        return accounts[vault][account].balanceAndRewardsSlot & StorageMasks.BALANCE_MASK;
    }

    /// @notice Updates the harvest fee percentage
    /// @param _harvestFeePercent New harvest fee percentage (scaled by 1e18)
    /// @custom:throws WhatWrongWithYou If total fees would exceed maximum
    function setHarvestFeePercent(uint256 _harvestFeePercent) external onlyOwner {
        (uint256 harvestFeePercent, uint256 donationPremiumPercent, uint256 protocolFeePercent) = _loadFees();
        require(_harvestFeePercent + donationPremiumPercent + protocolFeePercent <= MAX_FEE_PERCENT, WhatWrongWithYou());

        emit HarvestFeePercentSet(harvestFeePercent, _harvestFeePercent);

        // Update fees.
        fees.feesSlot = (_harvestFeePercent << 64) | (donationPremiumPercent << 96) | (protocolFeePercent << 128);
    }

    /// @notice Updates the donation premium percentage
    /// @param _donationFeePercent New donation premium percentage (scaled by 1e18)
    /// @custom:throws WhatWrongWithYou If total fees would exceed maximum
    function setDonationFeePercent(uint256 _donationFeePercent) external onlyOwner {
        (uint256 harvestFeePercent, uint256 donationPremiumPercent, uint256 protocolFeePercent) = _loadFees();
        require(_donationFeePercent + harvestFeePercent + protocolFeePercent <= MAX_FEE_PERCENT, WhatWrongWithYou());

        emit DonationFeePercentSet(donationPremiumPercent, _donationFeePercent);

        fees.feesSlot = (harvestFeePercent << 64) | (_donationFeePercent << 96) | (protocolFeePercent << 128);
    }

    /// @notice Updates the protocol fee percentage
    /// @param _protocolFeePercent New protocol fee percentage (scaled by 1e18)
    /// @custom:throws WhatWrongWithYou If total fees would exceed maximum
    function setProtocolFeePercent(uint256 _protocolFeePercent) external onlyOwner {
        (uint256 harvestFeePercent, uint256 donationPremiumPercent, uint256 protocolFeePercent) = _loadFees();
        require(_protocolFeePercent + harvestFeePercent + donationPremiumPercent <= MAX_FEE_PERCENT, WhatWrongWithYou());

        emit ProtocolFeePercentSet(protocolFeePercent, _protocolFeePercent);

        // Update fees.
        fees.feesSlot = (harvestFeePercent << 64) | (donationPremiumPercent << 96) | (_protocolFeePercent << 128);
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @dev Loads the current fee percentages from storage
    /// @return harvestFeePercent The current harvest fee percentage
    /// @return donationPremiumPercent The current donation premium percentage
    /// @return protocolFeePercent The current protocol fee percentage
    function _loadFees()
        internal
        view
        returns (uint256 harvestFeePercent, uint256 donationPremiumPercent, uint256 protocolFeePercent)
    {
        uint256 slot = fees.feesSlot;
        harvestFeePercent = slot & StorageMasks.HARVEST_FEE_MASK;
        donationPremiumPercent = (slot & StorageMasks.DONATION_FEE_MASK) >> 64;
        protocolFeePercent = (slot & StorageMasks.PROTOCOL_FEE_MASK) >> 128;
    }

    /// @notice Returns the current harvest fee percentage
    /// @return The harvest fee percentage
    function getHarvestFeePercent() public view returns (uint256) {
        return fees.feesSlot & StorageMasks.HARVEST_FEE_MASK;
    }

    /// @notice Returns the current donation premium percentage
    /// @return The donation premium percentage
    function getDonationPremiumPercent() public view returns (uint256) {
        return (fees.feesSlot & StorageMasks.DONATION_FEE_MASK) >> 64;
    }

    /// @notice Returns the current protocol fee percentage
    /// @return The protocol fee percentage
    function getProtocolFeePercent() public view returns (uint256) {
        return (fees.feesSlot & StorageMasks.PROTOCOL_FEE_MASK) >> 128;
    }

    /// @notice Claims accumulated protocol fees
    /// @dev Transfers fees to the configured fee receiver
    /// @custom:throws NoFeeReceiver If the fee receiver is not set
    function claimProtocolFees() external nonReentrant {
        address feeReceiver = IRegistry(REGISTRY).FEE_RECEIVER();
        require(feeReceiver != address(0), NoFeeReceiver());

        IERC20(REWARD_TOKEN).safeTransfer(feeReceiver, protocolFeesAccrued);

        emit ProtocolFeesClaimed(protocolFeesAccrued);

        protocolFeesAccrued = 0;
    }
}
