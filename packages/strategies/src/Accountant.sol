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

    /// @notice Scaling factor used for fixed-point arithmetic precision (1e18).
    uint256 public constant SCALING_FACTOR = 1e18;

    /// @notice The maximum fee percent.
    uint256 public constant MAX_FEE_PERCENT = 0.4e18; // 40%

    /// @notice The registry of addresses.
    address public immutable REGISTRY;

    /// @notice The reward token.
    address public immutable REWARD_TOKEN;

    /// @notice The harvest fee.
    uint256 public harvestFeePercent = 0.005e18; // 0.5%

    /// @notice The donation premium.
    uint256 public donationPremiumPercent = 0.005e18; // 0.5%

    /// @notice The protocol fee.
    uint256 public protocolFeePercent = 0.15e18; // 15%

    /// @notice The global harvest integral of all vaults.
    uint256 public globalHarvestIntegral;

    /// @notice The global pending rewards of all vaults.
    uint256 public globalPendingRewards;

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

    /// @notice The error thrown when the harvest integral is not reached.
    error HarvestIntegralNotReached();

    /// @notice The error thrown when the input is invalid.
    error WhatWrongWithYou();

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
    }

    /// @notice Function called by vaults to checkpoint the state of the vault on every account action.
    /// @param asset The asset address.
    /// @param from The address of the sender.
    /// @param to The address of the receiver.
    /// @param amount The amount of tokens transferred.
    /// @param pendingRewards The amount of pending rewards.
    /// @param claimed Whether the rewards are claimed or only pending.
    /// TODO: Maybe remove the reentrancy guard.
    function checkpoint(address asset, address from, address to, uint256 amount, uint256 pendingRewards, bool claimed)
        external nonReentrant
    {
        require(msg.sender == IRegistry(REGISTRY).vaults(asset), OnlyVault());

        PackedVault storage _vault = vaults[msg.sender];
        uint256 vaultSupplyAndIntegral = _vault.supplyAndIntegralSlot;

        uint256 supply = uint128(vaultSupplyAndIntegral & StorageMasks.SUPPLY_MASK);
        uint256 integral = uint128((vaultSupplyAndIntegral & StorageMasks.INTEGRAL_MASK) >> 128);

        if (pendingRewards > 0 && supply > 0) {
            if (!claimed) {
                /// If the rewards are already claimed, there's no need to update the global pending rewards.
                globalPendingRewards += pendingRewards;
            }

            uint256 totalFees =
                Math.mulDiv(pendingRewards, harvestFeePercent + donationPremiumPercent + protocolFeePercent, 1e18);
            pendingRewards -= totalFees;

            integral += uint128(Math.mulDiv(pendingRewards, SCALING_FACTOR, supply));
        }

        /// 1. Minting.
        if (from == address(0)) {
            supply += amount;
        }
        /// 2. Transferring. Update the "from" account.
        else {
            PackedAccount storage _from = accounts[msg.sender][from];
            uint256 accountBalanceAndRewards = _from.balanceAndRewardsSlot;

            uint256 balance = uint96(accountBalanceAndRewards & StorageMasks.BALANCE_MASK);
            uint256 accountIntegral = uint96((accountBalanceAndRewards & StorageMasks.ACCOUNT_INTEGRAL_MASK) >> 96);
            uint256 accountPendingRewards =
                uint64((accountBalanceAndRewards & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            accountPendingRewards += uint64(Math.mulDiv((integral - accountIntegral), balance, SCALING_FACTOR));
            balance -= amount;

            _from.balanceAndRewardsSlot = (balance & StorageMasks.BALANCE_MASK)
                | ((integral << 96) & StorageMasks.ACCOUNT_INTEGRAL_MASK)
                | ((accountPendingRewards << 192) & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK);
        }

        /// 3. Burning.
        if (to == address(0)) {
            supply -= amount;
        }
        /// 4. Transferring. Update the "to" account.
        else {
            PackedAccount storage _to = accounts[msg.sender][to];
            uint256 accountBalanceAndRewards = _to.balanceAndRewardsSlot;

            uint256 balance = uint96(accountBalanceAndRewards & StorageMasks.BALANCE_MASK);
            uint256 accountIntegral = uint96((accountBalanceAndRewards & StorageMasks.ACCOUNT_INTEGRAL_MASK) >> 96);
            uint256 accountPendingRewards =
                uint64((accountBalanceAndRewards & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            accountPendingRewards += uint64(Math.mulDiv((integral - accountIntegral), balance, SCALING_FACTOR));
            balance += amount;

            _to.balanceAndRewardsSlot = (balance & StorageMasks.BALANCE_MASK)
                | ((integral << 96) & StorageMasks.ACCOUNT_INTEGRAL_MASK)
                | ((accountPendingRewards << 192) & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK);
        }

        /// Update vault storage.
        _vault.supplyAndIntegralSlot =
            (supply & StorageMasks.SUPPLY_MASK) | ((integral << 128) & StorageMasks.INTEGRAL_MASK);
    }

    function claim(address[] calldata _vaults, address receiver) external nonReentrant {
        _claim(_vaults, msg.sender, receiver);
    }

    function claim(address[] calldata _vaults, address account, address receiver) external onlyAllowed nonReentrant {
        _claim(_vaults, account, receiver);
    }

    function _claim(address[] calldata _vaults, address account, address receiver) internal {
        uint256 amount = 0;

        address vault;

        uint256 vaultSupplyAndIntegral;
        uint256 integral;
        uint256 balance;

        uint256 accountIntegral;
        uint256 accountPendingRewards;
        uint256 accountBalanceAndRewards;

        uint256 vaultsLength = _vaults.length;
        for (uint256 i; i < vaultsLength; i++) {
            vault = _vaults[i];

            PackedVault storage _vault = vaults[vault];
            PackedAccount storage _account = accounts[vault][account];

            vaultSupplyAndIntegral = _vault.supplyAndIntegralSlot;
            integral = uint128((vaultSupplyAndIntegral & StorageMasks.INTEGRAL_MASK) >> 128);

            accountBalanceAndRewards = _account.balanceAndRewardsSlot;
            balance = uint96(accountBalanceAndRewards & StorageMasks.BALANCE_MASK);
            accountIntegral = uint96((accountBalanceAndRewards & StorageMasks.ACCOUNT_INTEGRAL_MASK) >> 96);
            accountPendingRewards =
                uint64((accountBalanceAndRewards & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            if (integral > accountIntegral) {
                amount += Math.mulDiv(integral - accountIntegral, balance, SCALING_FACTOR);
            }

            amount += accountPendingRewards;

            /// Update the account storage.
            _account.balanceAndRewardsSlot = (balance & StorageMasks.BALANCE_MASK)
            /// Update the account integral.
            | ((integral << 96) & StorageMasks.ACCOUNT_INTEGRAL_MASK)
            /// Reset the pending rewards.
            | ((0 << 192) & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK);
        }

        /// If there's no pending rewards, revert.
        require(amount != 0, NoPendingRewards());

        /// Transfer the rewards.
        SafeERC20.safeTransfer(IERC20(REWARD_TOKEN), receiver, amount);
    }

    function donate() external nonReentrant {
        require(globalPendingRewards != 0, NoPendingRewards());

        /// Transfer the pending rewards.
        SafeERC20.safeTransferFrom(IERC20(REWARD_TOKEN), msg.sender, address(this), globalPendingRewards);

        /// Update the donation integral and the donate amount.
        PackedDonation storage _donation = donations[msg.sender];
        uint256 donationAndIntegral = _donation.donationAndIntegralSlot;

        uint256 donation = uint128(donationAndIntegral & StorageMasks.DONATION_MASK);
        donation += globalPendingRewards;

        _donation.donationAndIntegralSlot = (donation & StorageMasks.DONATION_MASK)
            | ((globalHarvestIntegral << 128) & StorageMasks.DONATION_INTEGRAL_MASK);

        /// Emit the donation event.
        emit Donation(msg.sender, globalPendingRewards);

        /// Update the global pending rewards.
        globalPendingRewards = 0;
    }

    function claimDonation() external nonReentrant {
        PackedDonation storage _donation = donations[msg.sender];

        uint256 donationAndIntegral = _donation.donationAndIntegralSlot;
        uint256 integral = uint128((donationAndIntegral & StorageMasks.DONATION_INTEGRAL_MASK) >> 128);

        /// If the integral is not reached, revert to avoid liquidity issue.
        require(globalHarvestIntegral >= integral, HarvestIntegralNotReached());

        /// Calculate the premium.
        uint256 donation = uint128(donationAndIntegral & StorageMasks.DONATION_MASK);

        /// If there's no donation, revert.
        require(donation > 0, NoDonation());

        donation += Math.mulDiv(donation, donationPremiumPercent, 1e18);

        /// Transfer the original amount + premium.
        SafeERC20.safeTransfer(IERC20(REWARD_TOKEN), msg.sender, donation);

        /// Reset.
        _donation.donationAndIntegralSlot =
            (0 & StorageMasks.DONATION_MASK) | ((globalHarvestIntegral << 128) & StorageMasks.DONATION_INTEGRAL_MASK);

        /// Emit the claim donation event.
        emit ClaimDonation(msg.sender, donation);
    }

    function totalSupply(address vault) external view returns (uint256) {
        return uint128(vaults[vault].supplyAndIntegralSlot & StorageMasks.SUPPLY_MASK);
    }

    /// @notice Get the donation amount of an account including the premium.
    function getDonation(address account) external view returns (uint256 donation) {
        uint256 donationAndIntegral = donations[account].donationAndIntegralSlot;

        /// Calculate the premium.
        donation = uint128(donationAndIntegral & StorageMasks.DONATION_MASK);
        donation += Math.mulDiv(donation, donationPremiumPercent, 1e18);
    }

    function balanceOf(address vault, address account) external view returns (uint256) {
        return uint96(accounts[vault][account].balanceAndRewardsSlot & StorageMasks.BALANCE_MASK);
    }

    function setHarvestFeePercent(uint256 _harvestFeePercent) external onlyOwner {
        require(_harvestFeePercent + donationPremiumPercent + protocolFeePercent <= MAX_FEE_PERCENT, WhatWrongWithYou());

        emit HarvestFeePercentSet(harvestFeePercent, _harvestFeePercent);

        harvestFeePercent = _harvestFeePercent;
    }

    function setDonationFeePercent(uint256 _donationFeePercent) external onlyOwner {
        require(_donationFeePercent + harvestFeePercent + protocolFeePercent <= MAX_FEE_PERCENT, WhatWrongWithYou());

        emit DonationFeePercentSet(donationPremiumPercent, _donationFeePercent);

        donationPremiumPercent = _donationFeePercent;
    }

    function setProtocolFeePercent(uint256 _protocolFeePercent) external onlyOwner {
        require(_protocolFeePercent + harvestFeePercent + donationPremiumPercent <= MAX_FEE_PERCENT, WhatWrongWithYou());

        emit ProtocolFeePercentSet(protocolFeePercent, _protocolFeePercent);

        protocolFeePercent = _protocolFeePercent;
    }

    //////////////////////////////////////////////////////
    /// --- TODOS
    //////////////////////////////////////////////////////

    function harvest(address vault) external nonReentrant {}

    function claimProtocolFees() external nonReentrant {}
}
