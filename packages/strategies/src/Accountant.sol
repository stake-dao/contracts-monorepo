/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "src/interfaces/IRegistry.sol";
import "src/libraries/StorageMasks.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @notice The source of truth.
contract Accountant is ReentrancyGuardTransient {
    /// @notice Packed vault data structure into 2 slots for gas optimization
    /// @dev supplyAndIntegralSlot: [supply (128) | integral (128)]
    /// @dev pendingRewardsSlot: [pendingRewards (64)]
    struct PackedVault {
        uint256 supplyAndIntegralSlot; // slot1 -> supplyAndIntegralSlot
        uint256 pendingRewards;
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

    /// @notice The registry of vaults.
    address public immutable REGISTRY;

    /// @notice The reward token.
    address public immutable REWARD_TOKEN;

    /// @notice The harvest fee.
    uint256 public harvestFee;

    /// @notice The donation fee.
    uint256 public donationFee;

    /// @notice The global harvest integral of all vaults.
    uint256 public globalHarvestIntegral;

    /// @notice The global pending rewards of all vaults.
    uint256 public globalPendingRewards;

    /// @notice Whether the vault integral is updated before the accounts checkpoint.
    /// @notice Supply of vaults.
    /// @dev Vault address -> PackedVault.
    mapping(address => PackedVault) private vaults;

    /// @notice Donations of accounts.
    mapping(address => PackedDonation) private donations;

    /// @notice Balances of accounts per vault.
    /// @dev Vault address -> Account address -> PackedAccount.
    mapping(address => mapping(address => PackedAccount)) private accounts;

    /// @notice The error thrown when the caller is not a vault.
    error OnlyVault();

    /// @notice The error thrown when there is no donation.
    error NoDonation();

    /// @notice The error thrown when there is no pending rewards.
    error NoPendingRewards();

    /// @notice The error thrown when the harvest integral is not reached.
    error HarvestIntegralNotReached();

    constructor(address _registry, address _rewardToken) {
        REGISTRY = _registry;
        REWARD_TOKEN = _rewardToken;

        harvestFee = 0.05e18;

        /// 0.5%

        donationFee = 0.05e18;
        /// 0.5%
    }

    /// @notice Function called by vaults to checkpoint the state of the vault on every account action.
    /// @param asset The asset address.
    /// @param from The address of the sender.
    /// @param to The address of the receiver.
    /// @param amount The amount of tokens transferred.
    /// @param pendingRewards The amount of pending rewards.
    /// @param claimed Whether the rewards are claimed or only pending.
    function checkpoint(address asset, address from, address to, uint256 amount, uint256 pendingRewards, bool claimed)
        external
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

            uint256 totalFees = pendingRewards * (harvestFee + donationFee) / 1e18;
            pendingRewards -= totalFees;

            integral += uint128(pendingRewards * 1e18 / supply);
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
            uint256 accountPendingRewards = uint64((accountBalanceAndRewards & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            accountPendingRewards += uint64((integral - accountIntegral) * balance / supply);
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
            uint256 accountPendingRewards = uint64((accountBalanceAndRewards & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK) >> 192);

            accountPendingRewards += uint64((integral - accountIntegral) * balance / supply);
            balance += amount;

            _to.balanceAndRewardsSlot = (balance & StorageMasks.BALANCE_MASK)
                | ((integral << 96) & StorageMasks.ACCOUNT_INTEGRAL_MASK)
                | ((accountPendingRewards << 192) & StorageMasks.ACCOUNT_PENDING_REWARDS_MASK);
        }

        /// Update vault storage.
        _vault.supplyAndIntegralSlot =
            (supply & StorageMasks.SUPPLY_MASK) | ((integral << 128) & StorageMasks.INTEGRAL_MASK);
    }

    function donate() external nonReentrant {
        require(globalPendingRewards != 0, NoPendingRewards());

        /// Transfer the pending rewards.
        SafeERC20.safeTransferFrom(IERC20(REWARD_TOKEN), msg.sender, address(this), globalPendingRewards - 1);

        /// Update the donation integral and the donate amount.
        PackedDonation storage _donation = donations[msg.sender];
        uint256 donationAndIntegral = _donation.donationAndIntegralSlot;

        uint256 donation = uint128(donationAndIntegral & StorageMasks.DONATION_MASK);
        donation += globalPendingRewards;

        _donation.donationAndIntegralSlot = (donation & StorageMasks.DONATION_MASK)
            | ((globalHarvestIntegral << 128) & StorageMasks.DONATION_INTEGRAL_MASK);

        /// Update the global pending rewards.
        /// @dev Don't set to 0 to avoid extra gas cost from changing storage from non-zero to zero value.
        globalPendingRewards = 1;
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

        donation += donation * donationFee / 1e18;

        /// Transfer the original amount + premium.
        SafeERC20.safeTransfer(IERC20(REWARD_TOKEN), msg.sender, donation);

        /// Reset.
        _donation.donationAndIntegralSlot =
            (0 & StorageMasks.DONATION_MASK) | ((globalHarvestIntegral << 128) & StorageMasks.DONATION_INTEGRAL_MASK);
    }

    function totalSupply(address vault) external view returns (uint256) {
        return uint128(vaults[vault].supplyAndIntegralSlot & StorageMasks.SUPPLY_MASK);
    }

    /// @notice Get the donation amount of an account including the premium.
    function getDonation(address account) external view returns (uint256 donation) {
        uint256 donationAndIntegral = donations[account].donationAndIntegralSlot;

        /// Calculate the premium.
        donation = uint128(donationAndIntegral & StorageMasks.DONATION_MASK);
        donation += donation * donationFee / 1e18;
    }

    function balanceOf(address vault, address account) external view returns (uint256) {
        return uint96(accounts[vault][account].balanceAndRewardsSlot & StorageMasks.BALANCE_MASK);
    }
}
