// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, IERC20Metadata, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {StorageMasks} from "src/libraries/StorageMasks.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title RewardVault
/// @notice An ERC4626-compatible vault that manages deposits, withdrawals, and reward distributions.
/// @dev Implements:
///      1. ERC4626 minimal interface for deposits/withdrawals.
///      2. Integration with Registry (and therefore Strategy, Allocator).
///      3. Delegation of accounting to the Accountant contract.
///      4. Reward distribution logic (claimable rewards).
contract RewardVault is IERC4626, ERC20 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    ///////////////////////////////////////////////////////////////
    /// ~ EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when a new reward token is added
    /// @param rewardToken The address of the reward token
    /// @param distributor The address of the rewards distributor
    event RewardTokenAdded(address indexed rewardToken, address indexed distributor);

    /// @notice Emitted when rewards are notified for distribution
    /// @param _rewardsToken The address of the reward token
    /// @param _amount The amount of rewards to distribute
    /// @param _rewardRate The rate at which rewards will be distributed
    event RewardsDeposited(address indexed _rewardsToken, uint256 _amount, uint128 _rewardRate);

    ///////////////////////////////////////////////////////////////
    /// ~ ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice The error thrown when caller is not the owner or approved
    error NotApproved();

    /// @notice Error thrown when the caller is not allowed.
    error OnlyAllowed();

    /// @notice Error thrown when the reward token is not valid
    error InvalidRewardToken();

    /// @notice Error thrown when the calculated reward rate exceeds the maximum value
    error RewardRateOverflow();

    /// @notice Error thrown when attempting to add a reward token that already exists
    error RewardAlreadyExists();

    /// @notice Error thrown when the maximum number of reward tokens is exceeded.
    error MaxRewardTokensExceeded();

    /// @notice Error thrown when an unauthorized address attempts to distribute rewards
    error UnauthorizedRewardsDistributor();

    ///////////////////////////////////////////////////////////////
    /// ~ CONSTANTS & IMMUTABLES
    ///////////////////////////////////////////////////////////////

    /// @notice The protocol ID.
    bytes4 public immutable PROTOCOL_ID;

    /// @notice The maximum number of reward tokens that can be added.
    uint256 constant MAX_REWARD_TOKEN_COUNT = 10;

    ///////////////////////////////////////////////////////////////
    /// ~ STORAGE STRUCTURES
    ///////////////////////////////////////////////////////////////

    /// @notice Packed reward data structure into 2 slots for gas optimization
    /// @dev Slot 1: [rewardsDistributor (160) | rewardsDuration (32) | lastUpdateTime (32) | periodFinish (32)]
    ///      Slot 2: [rewardRate (128) | rewardPerTokenStored (128)]
    struct PackedReward {
        uint256 distributorAndDurationAndLastUpdateAndPeriodFinishSlot;
        uint256 rewardRateAndRewardPerTokenStoredSlot;
    }

    /// @notice Packed account data structure into 1 slot for gas optimization
    /// @dev [rewardPerTokenPaid (128) | claimable (128)]
    struct PackedAccount {
        uint256 rewardPerTokenPaidAndClaimableSlot;
    }

    ///////////////////////////////////////////////////////////////
    /// ~ STATE VARIABLES
    ///////////////////////////////////////////////////////////////

    /// @notice List of active reward tokens
    address[] public rewardTokens;

    /// @notice Mapping of reward token to its existence
    mapping(address => bool) public isRewardToken;

    /// @notice Mapping of reward token to its packed reward data
    mapping(address => PackedReward) private rewardData;

    /// @notice Account reward data mapping
    mapping(address => mapping(address => PackedAccount)) private accountData;

    /// @notice Initializes the vault with basic ERC20 metadata
    /// @dev Sets up the vault with a standard name and symbol prefix
    constructor(bytes4 protocolId) ERC20(string.concat("StakeDAO Vault"), string.concat("sd-vault")) {
        PROTOCOL_ID = protocolId;
    }

    ///////////////////////////////////////////////////////////////
    /// ~ EXTERNAL/PUBLIC USER-FACING - DEPOSIT & MINT
    ///////////////////////////////////////////////////////////////

    /// @notice Deposits assets into the vault and mints shares to `receiver`.
    /// @dev Handles deposit allocation through strategy and updates rewards.
    /// @param assets The amount of assets to deposit.
    /// @param receiver The address to receive the minted shares.
    /// @return The amount of assets deposited.
    function deposit(uint256 assets, address receiver) public returns (uint256) {
        if (receiver == address(0)) receiver = msg.sender;
        _deposit(msg.sender, receiver, assets, assets);
        return assets;
    }

    /// @notice Mints exact `shares` to `receiver` by depositing assets.
    /// @dev Functionally identical to deposit in this 1:1 implementation.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address to receive the minted shares.
    /// @return The amount of shares minted.
    function mint(uint256 shares, address receiver) public returns (uint256) {
        if (receiver == address(0)) receiver = msg.sender;
        _deposit(msg.sender, receiver, shares, shares);
        return shares;
    }

    /// @dev Internal function to deposit assets into the vault.
    ///      1. Update the reward state for the receiver.
    ///      2. Get the deposit allocation.
    ///      3. Transfer assets to strategy.
    ///      4. Strategy deposits.
    ///      5. Mint shares (accountant checkpoint).
    ///      6. Emit Deposit event.
    function _deposit(address account, address receiver, uint256 assets, uint256 shares) internal {
        _updateReward(receiver, address(0));

        IAllocator.Allocation memory allocation = allocator().getDepositAllocation(gauge(), assets);

        for (uint256 i = 0; i < allocation.targets.length; i++) {
            SafeERC20.safeTransferFrom(IERC20(asset()), account, allocation.targets[i], allocation.amounts[i]);
        }

        uint256 pendingRewards = strategy().deposit(allocation);

        _mint(receiver, shares, pendingRewards, allocation.harvested);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    ///////////////////////////////////////////////////////////////
    /// ~ EXTERNAL/PUBLIC USER-FACING - WITHDRAW & REDEEM
    ///////////////////////////////////////////////////////////////

    /// @notice Withdraws `assets` from the vault to `receiver` by burning shares from `owner`.
    /// @dev Checks allowances and calls strategy withdrawal logic.
    /// @param assets The amount of assets to withdraw.
    /// @param receiver The address to receive the assets.
    /// @param owner The address to burn shares from.
    /// @return The amount of assets withdrawn.
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256) {
        if (receiver == address(0)) receiver = owner;

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (assets > allowed) revert NotApproved();
            if (allowed != type(uint256).max) _spendAllowance(owner, msg.sender, assets);
        }

        _withdraw(owner, receiver, assets, assets);
        return assets;
    }

    /// @notice Redeems `shares` from `owner` and sends assets to `receiver`.
    /// @dev Checks allowances and calls strategy withdrawal logic.
    /// @param shares The amount of shares to redeem.
    /// @param receiver The address to receive the assets.
    /// @param owner The address to burn shares from.
    /// @return The amount of shares burned.
    function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
        if (receiver == address(0)) receiver = owner;

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (shares > allowed) revert NotApproved();
            if (allowed != type(uint256).max) _spendAllowance(owner, msg.sender, shares);
        }

        _withdraw(owner, receiver, shares, shares);
        return shares;
    }

    /// @dev Internal function to withdraw assets from the vault.
    /// 1. Update the reward state for the owner.
    /// 2. Get the withdrawal allocation.
    /// 3. Withdraw from the strategy.
    /// 4. Burn shares (accountant checkpoint).
    /// 5. Transfer the assets to the receiver.
    /// 6. Emit Withdraw event.
    function _withdraw(address owner, address receiver, uint256 assets, uint256 shares) internal {
        _updateReward(owner, address(0));

        IAllocator.Allocation memory allocation = allocator().getWithdrawAllocation(gauge(), assets);

        uint256 pendingRewards = strategy().withdraw(allocation);

        _burn(owner, shares, pendingRewards, allocation.harvested);

        SafeERC20.safeTransfer(IERC20(asset()), receiver, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    ///////////////////////////////////////////////////////////////
    /// ~ EXTERNAL/PUBLIC USER-FACING - REWARDS
    ///////////////////////////////////////////////////////////////

    /// @notice Claims multiple reward tokens in a single transaction.
    /// @param tokens An array of reward tokens to claim.
    /// @param receiver The address to receive the claimed rewards.
    /// @return amounts An array of amounts claimed for each token.
    function claim(address[] calldata tokens, address receiver) public returns (uint256[] memory amounts) {
        return _claim(msg.sender, tokens, receiver);
    }

    /// @notice Claims multiple reward tokens in a single transaction for a given account.
    /// @param account The account to claim rewards for.
    /// @param tokens An array of reward tokens to claim.
    /// @param receiver The address to receive the claimed rewards.
    /// @return amounts An array of amounts claimed for each token.
    function claim(address account, address[] calldata tokens, address receiver)
        public
        returns (uint256[] memory amounts)
    {
        require(registry().allowed(address(this), msg.sender, msg.sig), "OnlyAllowed");
        return _claim(account, tokens, receiver);
    }

    /// @dev Internal function to claim multiple reward tokens.
    ///      1. Update rewards for the account.
    ///      2. Reset the claimable amount and transfer out the rewards.
    ///      3. Return claimed amounts.
    function _claim(address account, address[] calldata tokens_, address receiver)
        internal
        returns (uint256[] memory amounts)
    {
        if (receiver == address(0)) receiver = account;

        // Make sure reward accounting is up to date.
        _updateReward(account, address(0));

        amounts = new uint256[](tokens_.length);

        for (uint256 i = 0; i < tokens_.length; i++) {
            address rewardToken = tokens_[i];
            if (!isRewardToken[rewardToken]) revert InvalidRewardToken();

            uint256 accountEarned = earned(account, rewardToken);
            if (accountEarned == 0) continue;

            // Reset claimable to zero & set rewardPerTokenPaid to current.
            accountData[account][rewardToken].rewardPerTokenPaidAndClaimableSlot =
                uint256(uint128(rewardPerToken(rewardToken))) & StorageMasks.ACCOUNT_REWARD_PER_TOKEN;

            SafeERC20.safeTransfer(IERC20(rewardToken), receiver, accountEarned);
            amounts[i] = accountEarned;
        }
        return amounts;
    }

    /// @notice Adds a new reward token to the vault.
    /// @param _rewardsToken The address of the reward token to add.
    /// @param _distributor The address authorized to distribute rewards.
    function addRewardToken(address _rewardsToken, address _distributor) external {
        require(registry().allowed(address(this), msg.sender, msg.sig), "OnlyAllowed");
        if (isRewardToken[_rewardsToken]) revert RewardAlreadyExists();
        if (rewardTokens.length >= MAX_REWARD_TOKEN_COUNT) revert MaxRewardTokensExceeded();

        rewardTokens.push(_rewardsToken);
        isRewardToken[_rewardsToken] = true;

        // Set default 7-day duration in bits 160-191.
        uint256 distributorAndDurationAndLastUpdateAndPeriodFinishSlot = (
            uint160(_distributor) & StorageMasks.REWARD_DISTRIBUTOR
        ) | ((uint256(7 days) << 160) & StorageMasks.REWARD_DURATION);

        rewardData[_rewardsToken].distributorAndDurationAndLastUpdateAndPeriodFinishSlot =
            distributorAndDurationAndLastUpdateAndPeriodFinishSlot;

        emit RewardTokenAdded(_rewardsToken, _distributor);
    }

    /// @notice Deposits rewards into the vault.
    /// @dev Handles reward rate updates and token transfers.
    /// @param _rewardsToken The reward token being distributed.
    /// @param _amount The amount of rewards to distribute.
    function depositRewards(address _rewardsToken, uint256 _amount) external {
        // Update reward state for all tokens first.
        _updateReward(address(0), address(0));

        if (getRewardsDistributor(_rewardsToken) != msg.sender) revert UnauthorizedRewardsDistributor();

        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint32 currentTime = uint32(block.timestamp);
        uint32 periodFinish = getPeriodFinish(_rewardsToken);
        uint32 rewardsDuration = getRewardsDuration(_rewardsToken);
        uint256 newRewardRate;

        if (currentTime >= periodFinish) {
            newRewardRate = _amount / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - currentTime;
            uint256 leftover = remaining * getRewardRate(_rewardsToken);
            newRewardRate = (_amount + leftover) / rewardsDuration;
        }

        if (newRewardRate > type(uint128).max) revert RewardRateOverflow();

        // First storage slot: distributor, duration, lastUpdate, periodFinish
        uint256 distributorSlot = (
            rewardData[_rewardsToken].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                & StorageMasks.REWARD_DISTRIBUTOR
        ) | ((uint256(rewardsDuration) << 160) & StorageMasks.REWARD_DURATION)
            | ((uint256(currentTime) << 192) & StorageMasks.REWARD_LAST_UPDATE)
            | ((uint256(currentTime + rewardsDuration) << 224) & StorageMasks.REWARD_PERIOD_FINISH);

        // Second storage slot: rewardRate, rewardPerTokenStored
        uint256 rateSlot = (getRewardPerTokenStored(_rewardsToken) & StorageMasks.REWARD_PER_TOKEN_STORED)
            | ((uint256(newRewardRate) << 128) & StorageMasks.REWARD_RATE);

        rewardData[_rewardsToken].distributorAndDurationAndLastUpdateAndPeriodFinishSlot = distributorSlot;
        rewardData[_rewardsToken].rewardRateAndRewardPerTokenStoredSlot = rateSlot;

        emit RewardsDeposited(_rewardsToken, _amount, uint128(newRewardRate));
    }

    ///////////////////////////////////////////////////////////////
    /// ~ INTERNAL REWARD UPDATES & HELPERS ~
    ///////////////////////////////////////////////////////////////

    /// @notice Internal function to update reward state for two accounts (optional).
    /// @param _from The account to update. (Can be address(0) if not needed)
    /// @param _to The account to update. (Can be address(0) if not needed)
    function _updateReward(address _from, address _to) internal {
        uint256 len = rewardTokens.length;
        uint32 currentTime = uint32(block.timestamp);

        for (uint256 i; i < len; i++) {
            address token = rewardTokens[i];
            uint256 newRewardPerToken = _updateRewardToken(token, currentTime);

            // Update account-specific data if _from is set
            if (_from != address(0)) {
                _updateAccountData(_from, token, newRewardPerToken);
            }
            // Update account-specific data if _to is set
            if (_to != address(0)) {
                _updateAccountData(_to, token, newRewardPerToken);
            }
        }
    }

    /// @dev Updates reward token state and returns new rewardPerToken.
    function _updateRewardToken(address token, uint32 currentTime) internal returns (uint256 newRewardPerToken) {
        PackedReward storage reward = rewardData[token];

        newRewardPerToken = rewardPerToken(token);

        // Clear old lastUpdate and set new lastUpdate to currentTime
        uint256 distributorSlot = (
            reward.distributorAndDurationAndLastUpdateAndPeriodFinishSlot & ~StorageMasks.REWARD_LAST_UPDATE
        ) | ((uint256(currentTime) << 192) & StorageMasks.REWARD_LAST_UPDATE);

        // Keep existing reward rate; update rewardPerTokenStored
        uint256 rateSlot = (reward.rewardRateAndRewardPerTokenStoredSlot & StorageMasks.REWARD_RATE)
            | (uint128(newRewardPerToken) & StorageMasks.REWARD_PER_TOKEN_STORED);

        reward.distributorAndDurationAndLastUpdateAndPeriodFinishSlot = distributorSlot;
        reward.rewardRateAndRewardPerTokenStoredSlot = rateSlot;
    }

    /// @dev Updates account data with new claimable rewards.
    function _updateAccountData(address account, address token, uint256 newRewardPerToken) internal {
        uint256 earnedAmount = earned(account, token);

        // Lower 128 bits: new rewardPerTokenPaid, Upper 128 bits: earned (claimable)
        accountData[account][token].rewardPerTokenPaidAndClaimableSlot = (
            uint128(newRewardPerToken) & StorageMasks.ACCOUNT_REWARD_PER_TOKEN
        ) | ((uint256(uint128(earnedAmount)) << 128) & StorageMasks.ACCOUNT_CLAIMABLE);
    }

    ///////////////////////////////////////////////////////////////
    /// ~ VIEW / PURE METHODS ~
    ///////////////////////////////////////////////////////////////

    /// @notice Returns the address of the underlying token.
    /// @dev Retrieves the token address from the clone's immutable args.
    function asset() public view returns (address) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address token;
        assembly {
            token := mload(add(args, 80))
        }
        return token;
    }

    /// @notice Returns the total amount of underlying assets (1:1 with total shares).
    function totalAssets() public view returns (uint256) {
        return totalSupply();
    }

    /// @notice Converts a given number of assets to the equivalent amount of shares (1:1).
    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    /// @notice Converts a given number of shares to the equivalent amount of assets (1:1).
    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    /// @notice Returns the amount of assets that would be received for a given amount of shares.
    function previewDeposit(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    /// @notice Returns the amount of shares that would be received for a given amount of assets.
    function previewMint(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    /// @notice Returns the amount of shares that would be received for a given amount of assets.
    function previewWithdraw(uint256 assets) public pure returns (uint256) {
        return convertToShares(assets);
    }

    /// @notice Returns the amount of assets that would be received for a given amount of shares.
    function previewRedeem(uint256 shares) public pure returns (uint256) {
        return convertToAssets(shares);
    }

    /// @notice Returns the maximum amount of assets that can be deposited.
    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Returns the maximum amount of shares that can be minted.
    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Returns the maximum amount of assets that can be withdrawn.
    function maxWithdraw(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    /// @notice Returns the maximum amount of shares that can be redeemed.
    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    /// @notice Returns the distributor address for a given reward token.
    function getRewardsDistributor(address token) public view returns (address) {
        return address(
            uint160(
                rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                    & StorageMasks.REWARD_DISTRIBUTOR
            )
        );
    }

    /// @notice Returns the duration of the rewards distribution for a given reward token.
    function getRewardsDuration(address token) public view returns (uint32) {
        return uint32(
            (rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot & StorageMasks.REWARD_DURATION)
                >> 160
        );
    }

    /// @notice Returns the last update time for a given reward token.
    function getLastUpdateTime(address token) public view returns (uint32) {
        return uint32(
            (rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot & StorageMasks.REWARD_LAST_UPDATE)
                >> 192
        );
    }

    /// @notice Returns the period finish time for a given reward token.
    function getPeriodFinish(address token) public view returns (uint32) {
        return uint32(
            (
                rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                    & StorageMasks.REWARD_PERIOD_FINISH
            ) >> 224
        );
    }

    /// @notice Returns the reward rate for a given reward token.
    function getRewardRate(address token) public view returns (uint128) {
        return uint128((rewardData[token].rewardRateAndRewardPerTokenStoredSlot & StorageMasks.REWARD_RATE) >> 128);
    }

    /// @notice Returns the reward per token stored for a given reward token.
    function getRewardPerTokenStored(address token) public view returns (uint128) {
        return uint128(rewardData[token].rewardRateAndRewardPerTokenStoredSlot & StorageMasks.REWARD_PER_TOKEN_STORED);
    }

    /// @notice Returns the last time reward applicable for a given reward token.
    function lastTimeRewardApplicable(address token) public view returns (uint256) {
        return Math.min(block.timestamp, getPeriodFinish(token));
    }

    /// @notice Returns the reward per token for a given reward token.
    function rewardPerToken(address token) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return getRewardPerTokenStored(token);
        }
        return getRewardPerTokenStored(token)
            + ((lastTimeRewardApplicable(token) - getLastUpdateTime(token)) * getRewardRate(token) * 1e18 / _totalSupply);
    }

    /// @notice Returns the earned reward for a given account and reward token.
    function earned(address account, address token) public view returns (uint256) {
        PackedAccount storage accountDataValue = accountData[account][token];
        uint256 rewardPerTokenPaid =
            accountDataValue.rewardPerTokenPaidAndClaimableSlot & StorageMasks.ACCOUNT_REWARD_PER_TOKEN;
        uint256 claimable =
            (accountDataValue.rewardPerTokenPaidAndClaimableSlot & StorageMasks.ACCOUNT_CLAIMABLE) >> 128;

        uint256 newEarned = balanceOf(account) * (rewardPerToken(token) - rewardPerTokenPaid) / 1e18;
        return claimable + newEarned;
    }

    /// @notice Returns the reward for a given reward token for the duration of the rewards distribution.
    function getRewardForDuration(address token) external view returns (uint256) {
        return getRewardRate(token) * getRewardsDuration(token);
    }

    /// @notice Updates reward state for an account (public version).
    /// @param account The account to update rewards for.
    function updateReward(address account) external {
        _updateReward(account, address(0));
    }

    ///////////////////////////////////////////////////////////////
    /// ~ PROTOCOL_CONTROLLER / CLONE ARGUMENT GETTERS ~
    ///////////////////////////////////////////////////////////////

    /// @notice Returns the registry.
    function registry() public view returns (IProtocolController _registry) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _registry := mload(add(args, 20))
        }
    }

    /// @notice Returns the accountant.
    function accountant() public view returns (IAccountant _accountant) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _accountant := mload(add(args, 40))
        }
    }

    /// @notice Returns the gauge.
    function gauge() public view returns (address _gauge) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _gauge := mload(add(args, 60))
        }
    }

    /// @notice Returns the allocator.
    function allocator() public view returns (IAllocator _allocator) {
        return IAllocator(registry().allocator(PROTOCOL_ID));
    }

    /// @notice Returns the strategy.
    function strategy() public view returns (IStrategy _strategy) {
        return IStrategy(registry().strategy(PROTOCOL_ID));
    }

    ///////////////////////////////////////////////////////////////
    /// ~ ERC20 OVERRIDES ~
    ///////////////////////////////////////////////////////////////

    /// @notice Used by ERC20 transfers to update balances and reward state.
    /// @dev Delegates balance updates to the Accountant, then updates rewards.
    function _update(address from, address to, uint256 amount) internal override {
        // 1. Update Balances via Accountant.
        accountant().checkpoint(gauge(), from, to, amount, 0, false);

        // 2. Update Reward State.
        _updateReward(from, to);

        // 3. Emit Transfer event.
        emit Transfer(from, to, amount);
    }

    /// @dev Mints shares (accountant checkpoint).
    function _mint(address to, uint256 amount, uint256 pendingRewards, bool harvested) internal {
        accountant().checkpoint(gauge(), address(0), to, amount, pendingRewards, harvested);
    }

    /// @dev Burns shares (accountant checkpoint).
    function _burn(address from, uint256 amount, uint256 pendingRewards, bool harvested) internal {
        accountant().checkpoint(gauge(), from, address(0), amount, pendingRewards, harvested);
    }

    /// @notice Returns the name of the vault.
    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("StakeDAO ", IERC20Metadata(asset()).name(), " Vault");
    }

    /// @notice Returns the symbol of the vault.
    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("sd-", IERC20Metadata(asset()).symbol(), "-vault");
    }

    /// @notice Returns the number of decimals of the vault.
    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }

    /// @notice Returns the total supply of the vault.
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return accountant().totalSupply(address(this));
    }

    /// @notice Returns the balance of the vault for a given account.
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return accountant().balanceOf(address(this), account);
    }
}
