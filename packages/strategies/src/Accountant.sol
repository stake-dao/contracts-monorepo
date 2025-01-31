/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "src/interfaces/IRegistry.sol";
import "src/libraries/StorageMasks.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice The source of truth.
contract Accountant is ReentrancyGuardTransient, Ownable2Step {
    /// @notice Packed vault data structure into 2 slots for gas optimization
    /// @dev supplyAndIntegralSlot: [supply (128) | integral (128)]
    struct PackedVault {
        uint256 supplyAndIntegralSlot; // slot1 -> supplyAndIntegralSlot
    }

    /// @notice Packed account data structure into 1 slot for gas optimization
    /// @dev balanceAndRewardsSlot: [balance (96) | integral (96) | pendingRewards (64)]
    struct PackedAccount {
        uint256 balanceAndRewardsSlot; // slot -> balanceAndRewardsSlot
    }

    /// @notice Packed donation data structure into 1 slot for gas optimization
    /// @dev donationAndIntegralSlot: [donation (128) | integral (128)]
    struct PackedDonation {
        uint256 donationAndIntegralSlot;
    }

    /// @notice Packed fees and premiums data structure into 1 slot for gas optimization
    /// @dev feesSlot: [harvestFeePercent (64) | donationPremiumPercent (64) | protocolFeePercent (64)]
    struct PackedFees {
        uint256 feesSlot;
    }

    /// @notice Scaling factor used for fixed-point arithmetic precision (1e18).
    uint256 public constant SCALING_FACTOR = 1e18;

    /// @notice The maximum fee percent.
    uint256 public constant MAX_FEE_PERCENT = 0.4e18; // 40%

    /// @notice The registry of addresses.
    address public immutable REGISTRY;

    /// @notice The reward token.
    address public immutable REWARD_TOKEN;

    /// @notice The fees and premiums.
    PackedFees public fees;

    /// @notice The global pending rewards of all vaults.
    uint256 public globalPendingRewards;

    /// @notice The global harvest integral of all vaults.
    uint256 public globalHarvestIntegral;

    /// @notice Whether the vault integral is updated before the accounts checkpoint.
    /// @notice Supply of vaults.
    /// @dev Vault address -> PackedVault.
    mapping(address vault => PackedVault vaultData) private vaults;

    /// @notice Donations of accounts.
    mapping(address account => PackedDonation donationData) private donations;

    /// @notice Balances of accounts per vault.
    /// @dev Vault address -> Account address -> PackedAccount.
    mapping(address vault => mapping(address account => PackedAccount accountData)) private accounts;

    /// @notice The error thrown when the caller is not allowed.
    error OnlyAllowed();

    /// @notice The error thrown when the caller is not a vault.
    error OnlyVault();

    /// @notice The error thrown when there is no donation.
    error NoDonation();

    /// @notice The error thrown when there is no pending rewards.
    error NoPendingRewards();

    /// @notice The error thrown when the input is invalid.
    error WhatWrongWithYou();

    /// @notice The error thrown when the harvest integral is not reached.
    error HarvestIntegralNotReached();

    /// @notice The event emitted when an account donates.
    event Donation(address indexed donator, uint256 amount);

    /// @notice The event emitted when an account claims rewards.
    event ClaimDonation(address indexed account, uint256 amount);

    /// @notice The event emitted when a vault harvests rewards.
    event Harvest(address indexed vault, uint256 amount);

    /// @notice The event emitted when the harvest fee percent is set.
    event HarvestFeePercentSet(uint256 oldHarvestFeePercent, uint256 newHarvestFeePercent);

    /// @notice The event emitted when the donation fee percent is set.
    event DonationFeePercentSet(uint256 oldDonationFeePercent, uint256 newDonationFeePercent);

    /// @notice The event emitted when the protocol fee percent is set.
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

    /// @notice Function called by vaults to checkpoint the state of the vault on every account action.
    /// @dev This function handles four types of operations:
    ///      1. Minting (from = address(0)): Creates new tokens
    ///      2. Burning (to = address(0)): Destroys tokens
    ///      3. Transfers: Updates balances and rewards for both sender and receiver
    ///      4. Reward Distribution: Processes pending rewards if any exist
    /// @param asset The underlying asset address of the vault
    /// @param from The source address (address(0) for minting)
    /// @param to The destination address (address(0) for burning)
    /// @param amount The amount of tokens being transferred/minted/burned
    /// @param pendingRewards New rewards to be distributed to the vault
    /// @param claimed Whether these rewards were already claimed (true) or need to be added to global pending (false)
    /// @custom:throws OnlyVault If caller is not the registered vault for the asset
    function checkpoint(address asset, address from, address to, uint256 amount, uint256 pendingRewards, bool claimed)
        external
        nonReentrant
    {
        // Validate caller is the registered vault for this asset
        require(IRegistry(REGISTRY).vaults(asset) == msg.sender, OnlyVault());

        PackedVault storage _vault = vaults[msg.sender];
        uint256 vaultSupplyAndIntegral = _vault.supplyAndIntegralSlot;

        uint256 supply = uint128(vaultSupplyAndIntegral & StorageMasks.SUPPLY_MASK);
        uint256 integral = uint128((vaultSupplyAndIntegral & StorageMasks.INTEGRAL_MASK) >> 128);

        // Process any pending rewards if they exist and there is supply
        if (pendingRewards > 0 && supply > 0) {
            if (!claimed) {
                // Only update global pending rewards for unclaimed rewards
                globalPendingRewards += pendingRewards;
            }

            uint256 feeSlot = fees.feesSlot;

            uint256 harvestFeePercent = uint64(feeSlot & StorageMasks.HARVEST_FEE_MASK);
            uint256 protocolFeePercent = uint64((feeSlot & StorageMasks.PROTOCOL_FEE_MASK) >> 128);
            uint256 donationPremiumPercent = uint64((feeSlot & StorageMasks.DONATION_FEE_MASK) >> 64);

            // Calculate and deduct fees
            uint256 totalFees =
                Math.mulDiv(pendingRewards, harvestFeePercent + donationPremiumPercent + protocolFeePercent, 1e18);
            pendingRewards -= totalFees;

            // Update integral with new rewards per token
            integral += uint128(Math.mulDiv(pendingRewards, SCALING_FACTOR, supply));
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
        _vault.supplyAndIntegralSlot =
            (supply & StorageMasks.SUPPLY_MASK) | ((integral << 128) & StorageMasks.INTEGRAL_MASK);
    }

    /// @dev Helper function to update an account's balance and rewards
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

        uint256 balance = uint96(accountBalanceAndRewards & StorageMasks.BALANCE_MASK);
        uint256 accountIntegral = uint96((accountBalanceAndRewards & StorageMasks.ACCOUNT_INTEGRAL_MASK) >> 96);
        uint256 accountPendingRewards =
            uint64((accountBalanceAndRewards & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK) >> 192);

        // Update pending rewards based on the integral difference
        accountPendingRewards += uint64(Math.mulDiv((currentIntegral - accountIntegral), balance, SCALING_FACTOR));

        // Update balance
        balance = isDecrease ? balance - amount : balance + amount;

        // Pack and store updated values
        _account.balanceAndRewardsSlot = (balance & StorageMasks.BALANCE_MASK)
            | ((currentIntegral << 96) & StorageMasks.ACCOUNT_INTEGRAL_MASK)
            | ((accountPendingRewards << 192) & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK);
    }

    /// @notice Claims rewards from multiple vaults and sends them to a specified receiver
    /// @dev This is the user-facing claim function that only allows claiming for the sender
    /// @param _vaults Array of vault addresses to claim rewards from
    /// @param receiver Address that will receive the claimed rewards
    /// @custom:throws NoPendingRewards If there are no rewards to claim
    function claim(address[] calldata _vaults, address receiver) external nonReentrant {
        _claim(_vaults, msg.sender, receiver);
    }

    /// @notice Claims rewards on behalf of an account (restricted to allowed callers)
    /// @dev This is the admin/operator claim function that can claim for any account
    /// @param _vaults Array of vault addresses to claim rewards from
    /// @param account Address to claim rewards for
    /// @param receiver Address that will receive the claimed rewards
    /// @custom:throws OnlyAllowed If caller is not allowed to claim on behalf of others
    /// @custom:throws NoPendingRewards If there are no rewards to claim
    function claim(address[] calldata _vaults, address account, address receiver) external onlyAllowed nonReentrant {
        _claim(_vaults, account, receiver);
    }

    /// @dev Internal implementation of the claim functionality
    /// @dev For each vault:
    ///      1. Loads the vault and account data
    ///      2. Calculates new rewards based on integral differences
    ///      3. Adds any pending rewards
    ///      4. Updates account state and resets pending rewards
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
            vaultSupplyAndIntegral = _vault.supplyAndIntegralSlot;
            integral = uint128((vaultSupplyAndIntegral & StorageMasks.INTEGRAL_MASK) >> 128);

            // Unpack account data
            accountBalanceAndRewards = _account.balanceAndRewardsSlot;
            balance = uint96(accountBalanceAndRewards & StorageMasks.BALANCE_MASK);
            accountIntegral = uint96((accountBalanceAndRewards & StorageMasks.ACCOUNT_INTEGRAL_MASK) >> 96);
            accountPendingRewards =
                uint64((accountBalanceAndRewards & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            // Add new rewards if integral has increased
            if (integral > accountIntegral) {
                amount += Math.mulDiv(integral - accountIntegral, balance, SCALING_FACTOR);
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
        SafeERC20.safeTransfer(IERC20(REWARD_TOKEN), receiver, amount);
    }

    /// @notice Allows users to donate their pending rewards to the protocol
    /// @dev When a user donates:
    ///      1. Their donation is recorded with the current harvest integral
    ///      2. They can later claim back their donation plus a premium
    ///      3. The donation helps provide liquidity for the reward system
    /// @custom:throws NoPendingRewards If there are no global pending rewards
    function donate() external nonReentrant {
        require(globalPendingRewards != 0, NoPendingRewards());

        // Transfer pending rewards from donor
        SafeERC20.safeTransferFrom(IERC20(REWARD_TOKEN), msg.sender, address(this), globalPendingRewards);

        // Update donation storage
        PackedDonation storage _donation = donations[msg.sender];
        uint256 donationAndIntegral = _donation.donationAndIntegralSlot;

        // Add to existing donation amount
        uint256 donation = uint128(donationAndIntegral & StorageMasks.DONATION_MASK);
        donation += globalPendingRewards;

        // Store donation with current harvest integral
        _donation.donationAndIntegralSlot = (donation & StorageMasks.DONATION_MASK)
            | ((globalHarvestIntegral << 128) & StorageMasks.DONATION_INTEGRAL_MASK);

        emit Donation(msg.sender, globalPendingRewards);

        // Reset global pending rewards
        globalPendingRewards = 0;
    }

    /// @notice Allows users to claim back their donations plus earned premium
    /// @dev The claim process:
    ///      1. Verifies the global harvest integral has reached the donation's integral
    ///      2. Calculates total claimable amount (original donation + premium)
    ///      3. Transfers the total amount to the donor
    ///      4. Resets the donation while preserving the latest harvest integral
    /// @custom:throws HarvestIntegralNotReached If global harvest integral is less than donation integral
    /// @custom:throws NoDonation If the user has no donation to claim
    function claimDonation() external nonReentrant {
        PackedDonation storage _donation = donations[msg.sender];
        uint256 donationAndIntegral = _donation.donationAndIntegralSlot;

        // Unpack donation data
        uint256 integral = uint128((donationAndIntegral & StorageMasks.DONATION_INTEGRAL_MASK) >> 128);
        uint256 donation = uint128(donationAndIntegral & StorageMasks.DONATION_MASK);

        // Verify harvest integral has been reached
        require(globalHarvestIntegral >= integral, HarvestIntegralNotReached());

        // Verify donation exists
        require(donation != 0, NoDonation());

        // Get donation premium percent
        uint256 donationPremiumPercent = getDonationPremiumPercent();

        // Calculate total claimable amount including premium
        uint256 totalClaimable = donation + Math.mulDiv(donation, donationPremiumPercent, 1e18);

        // Transfer total amount to donor
        SafeERC20.safeTransfer(IERC20(REWARD_TOKEN), msg.sender, totalClaimable);

        // Reset donation while preserving latest harvest integral
        _donation.donationAndIntegralSlot =
            (0 & StorageMasks.DONATION_MASK) | ((globalHarvestIntegral << 128) & StorageMasks.DONATION_INTEGRAL_MASK);

        emit ClaimDonation(msg.sender, totalClaimable);
    }

    /// @notice Returns the total supply of tokens in a vault
    /// @param vault The vault address to query
    /// @return The total supply of tokens in the vault
    function totalSupply(address vault) external view returns (uint256) {
        return uint128(vaults[vault].supplyAndIntegralSlot & StorageMasks.SUPPLY_MASK);
    }

    /// @notice Calculates the claimable donation amount including premium
    /// @dev The premium is calculated as a percentage of the original donation
    /// @param account The account to check donation for
    /// @return donation The total claimable amount (original + premium)
    function getDonation(address account) external view returns (uint256 donation) {
        uint256 donationAndIntegral = donations[account].donationAndIntegralSlot;

        // Get original donation amount
        donation = uint128(donationAndIntegral & StorageMasks.DONATION_MASK);

        // Get donation premium percent
        uint256 donationPremiumPercent = getDonationPremiumPercent();

        // Add premium
        donation += Math.mulDiv(donation, donationPremiumPercent, 1e18);
    }

    /// @notice Returns the token balance of an account in a specific vault
    /// @param vault The vault address to query
    /// @param account The account address to check
    /// @return The account's token balance in the vault
    function balanceOf(address vault, address account) external view returns (uint256) {
        return uint96(accounts[vault][account].balanceAndRewardsSlot & StorageMasks.BALANCE_MASK);
    }

    /// @notice Updates the harvest fee percentage
    /// @dev The total of all fees must not exceed MAX_FEE_PERCENT
    /// @param _harvestFeePercent New harvest fee percentage (scaled by 1e18)
    /// @custom:throws WhatWrongWithYou If total fees would exceed maximum
    function setHarvestFeePercent(uint256 _harvestFeePercent) external onlyOwner {
        uint256 harvestFeePercent = getHarvestFeePercent();
        uint256 donationPremiumPercent = getDonationPremiumPercent();
        uint256 protocolFeePercent = getProtocolFeePercent();

        require(_harvestFeePercent + donationPremiumPercent + protocolFeePercent <= MAX_FEE_PERCENT, WhatWrongWithYou());

        emit HarvestFeePercentSet(harvestFeePercent, _harvestFeePercent);

        // Update fees.
        fees.feesSlot = (_harvestFeePercent << 64) | (donationPremiumPercent << 96) | (protocolFeePercent << 128);
    }

    /// @notice Updates the donation premium percentage
    /// @dev The total of all fees must not exceed MAX_FEE_PERCENT
    /// @param _donationFeePercent New donation premium percentage (scaled by 1e18)
    /// @custom:throws WhatWrongWithYou If total fees would exceed maximum
    function setDonationFeePercent(uint256 _donationFeePercent) external onlyOwner {
        uint256 harvestFeePercent = getHarvestFeePercent();
        uint256 protocolFeePercent = getProtocolFeePercent();
        uint256 donationPremiumPercent = getDonationPremiumPercent();

        require(_donationFeePercent + harvestFeePercent + protocolFeePercent <= MAX_FEE_PERCENT, WhatWrongWithYou());

        emit DonationFeePercentSet(donationPremiumPercent, _donationFeePercent);

        fees.feesSlot = (harvestFeePercent << 64) | (_donationFeePercent << 96) | (protocolFeePercent << 128);
    }

    /// @notice Updates the protocol fee percentage
    /// @dev The total of all fees must not exceed MAX_FEE_PERCENT
    /// @param _protocolFeePercent New protocol fee percentage (scaled by 1e18)
    /// @custom:throws WhatWrongWithYou If total fees would exceed maximum
    function setProtocolFeePercent(uint256 _protocolFeePercent) external onlyOwner {
        uint256 harvestFeePercent = getHarvestFeePercent();
        uint256 donationPremiumPercent = getDonationPremiumPercent();
        uint256 protocolFeePercent = getProtocolFeePercent();

        require(_protocolFeePercent + harvestFeePercent + donationPremiumPercent <= MAX_FEE_PERCENT, WhatWrongWithYou());

        emit ProtocolFeePercentSet(protocolFeePercent, _protocolFeePercent);

        // Update fees.
        fees.feesSlot = (harvestFeePercent << 64) | (donationPremiumPercent << 96) | (_protocolFeePercent << 128);
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Returns the harvest fee percent
    /// @return The harvest fee percent
    function getHarvestFeePercent() public view returns (uint256) {
        return uint64(fees.feesSlot & StorageMasks.HARVEST_FEE_MASK);
    }

    /// @notice Returns the donation premium percent
    /// @return The donation premium percent
    function getDonationPremiumPercent() public view returns (uint256) {
        return uint64((fees.feesSlot & StorageMasks.DONATION_FEE_MASK) >> 64);
    }

    /// @notice Returns the protocol fee percent
    /// @return The protocol fee percent
    function getProtocolFeePercent() public view returns (uint256) {
        return uint64((fees.feesSlot & StorageMasks.PROTOCOL_FEE_MASK) >> 128);
    }

    //////////////////////////////////////////////////////
    /// --- TODOS
    //////////////////////////////////////////////////////

    function harvest(address vault) external nonReentrant {}

    function claimProtocolFees() external nonReentrant {}
}