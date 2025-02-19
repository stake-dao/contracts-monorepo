/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, IERC20Metadata, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IRegistry} from "src/interfaces/IRegistry.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {StorageMasks} from "src/libraries/StorageMasks.sol";

/// @title Reward Vault
/// @notice An ERC4626-compatible vault that manages deposits, withdrawals, and reward distributions
/// @dev Implements core vault functionality with:
///      - ERC4626 minimal interface for deposits and withdrawals
///      - Integration with Registry for contract addresses
///      - Delegation of accounting to Accountant contract
///      - Strategy integration for yield generation
///      - Reward distribution and claiming functionality
contract RewardVault is IERC4626, ERC20 {
    using Math for uint256;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////

    /// @notice Emitted when a new reward token is added
    /// @param rewardToken The address of the reward token
    /// @param distributor The address of the rewards distributor
    event RewardTokenAdded(address indexed rewardToken, address indexed distributor);

    /// @notice Emitted when rewards are notified for distribution
    /// @param _rewardsToken The address of the reward token
    /// @param _amount The amount of rewards to distribute
    /// @param _rewardRate The rate at which rewards will be distributed
    event RewardsDeposited(address indexed _rewardsToken, uint256 _amount, uint128 _rewardRate);

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice The error thrown when caller is not the owner or approved
    /// @dev Access control for token operations
    error NotApproved();

    /// @notice Error thrown when the caller is not allowed.
    error OnlyAllowed();

    /// @notice Error thrown when the calculated reward rate exceeds the maximum value
    /// @dev Prevents overflow in reward rate calculations
    error RewardRateOverflow();

    /// @notice Error thrown when attempting to add a reward token that already exists
    /// @dev Prevents duplicate reward token entries
    error RewardAlreadyExists();

    /// @notice Error thrown when the maximum number of reward tokens is exceeded.
    error MaxRewardTokensExceeded();

    /// @notice Error thrown when an unauthorized address attempts to distribute rewards
    /// @dev Access control for reward distribution
    error UnauthorizedRewardsDistributor();

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice The maximum number of reward tokens that can be added.
    uint256 constant MAX_REWARD_TOKEN_COUNT = 10;

    //////////////////////////////////////////////////////
    /// --- STORAGE STRUCTURES
    //////////////////////////////////////////////////////

    /// @notice Packed reward data structure into 2 slots for gas optimization
    /// @dev Slot 1: [rewardsDistributor (160) | rewardsDuration (32) | lastUpdateTime (32) | periodFinish (32)]
    /// @dev Slot 2: [rewardRate (128) | rewardPerTokenStored (128)]
    struct PackedReward {
        uint256 distributorAndDurationAndLastUpdateAndPeriodFinishSlot;
        uint256 rewardRateAndRewardPerTokenStoredSlot;
    }

    /// @notice Packed account data structure into 1 slot for gas optimization
    /// @dev [rewardPerTokenPaid (128) | claimable (128)]
    struct PackedAccount {
        uint256 rewardPerTokenPaidAndClaimableSlot;
    }

    //////////////////////////////////////////////////////
    /// --- STATE VARIABLES
    //////////////////////////////////////////////////////

    /// @notice List of active reward tokens
    /// @dev Array of reward token addresses that can be distributed
    address[] public rewardTokens;

    /// @notice Mapping of reward token to its existence
    /// @dev Used to check if a reward token is already added
    mapping(address => bool) public isRewardToken;

    /// @notice Mapping of reward token to its packed reward data
    /// @dev Stores reward distribution parameters and state for each token
    mapping(address => PackedReward) private rewardData;

    /// @notice Account reward data mapping
    /// @dev Maps user addresses to their reward state for each token
    mapping(address => mapping(address => PackedAccount)) private accountData;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the vault with basic ERC20 metadata
    /// @dev Sets up the vault with a standard name and symbol prefix
    constructor() ERC20(string.concat("StakeDAO Vault"), string.concat("sd-vault")) {}

    //////////////////////////////////////////////////////
    /// --- CORE VAULT FUNCTIONALITY
    //////////////////////////////////////////////////////

    /// @notice Returns the address of the underlying token
    /// @dev Retrieves the token address from the clone's immutable args
    /// @return The address of the ERC20 token that the vault accepts
    function asset() public view returns (address) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address token;
        assembly {
            token := mload(add(args, 80))
        }
        return token;
    }

    /// @notice Returns the total amount of underlying assets held by the vault
    /// @dev In this implementation, total assets equals total supply for simplicity
    /// @return The total amount of underlying assets
    function totalAssets() public view returns (uint256) {
        return totalSupply();
    }

    /// @notice Converts a given number of assets to the equivalent amount of shares
    /// @dev 1:1 conversion ratio in this implementation
    /// @param assets The number of assets to convert
    /// @return The amount of shares equivalent to the assets
    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    /// @notice Converts a given number of shares to the equivalent amount of assets
    /// @dev 1:1 conversion ratio in this implementation
    /// @param shares The number of shares to convert
    /// @return The amount of assets equivalent to the shares
    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    //////////////////////////////////////////////////////
    /// --- DEPOSIT FUNCTIONALITY
    //////////////////////////////////////////////////////

    /// @notice Returns the maximum amount of assets that can be deposited
    /// @dev No upper limit in this implementation
    /// @return The maximum amount of assets (uint256.max)
    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Returns the maximum amount of shares that can be minted
    /// @dev No upper limit in this implementation
    /// @return The maximum amount of shares (uint256.max)
    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Simulates the amount of shares that would be minted for a deposit
    /// @dev 1:1 ratio between assets and shares in this implementation
    /// @param assets The amount of assets to simulate deposit for
    /// @return The amount of shares that would be minted
    function previewDeposit(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    /// @notice Simulates the amount of assets needed for a mint
    /// @dev 1:1 ratio between assets and shares in this implementation
    /// @param shares The amount of shares to simulate minting
    /// @return The amount of assets that would be needed
    function previewMint(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    /// @notice Deposits assets into the vault and mints shares to receiver
    /// @dev Handles deposit allocation through strategy and updates rewards
    /// @param assets The amount of assets to deposit
    /// @param receiver The address to receive the minted shares
    /// @return assets The amount of assets deposited
    function deposit(uint256 assets, address receiver) public returns (uint256) {
        if (receiver == address(0)) receiver = msg.sender;

        _deposit(msg.sender, receiver, assets, assets);
        return assets;
    }

    /// @notice Mints exact shares to receiver by depositing assets
    /// @dev Functionally identical to deposit in this implementation
    /// @param shares The amount of shares to mint
    /// @param receiver The address to receive the minted shares
    /// @return shares The amount of shares minted
    function mint(uint256 shares, address receiver) public returns (uint256) {
        if (receiver == address(0)) receiver = msg.sender;

        _deposit(msg.sender, receiver, shares, shares);
        return shares;
    }

    /// @notice Internal function to deposit assets into the vault
    /// @dev Handles the actual deposit logic including strategy integration
    /// @param account The account providing the assets
    /// @param receiver The account receiving the shares
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of shares to mint
    function _deposit(address account, address receiver, uint256 assets, uint256 shares) internal virtual {
        /// 1. Update the reward state for the receiver.
        _updateReward(receiver, address(0));

        /// 2. Get the allocation.
        IAllocator.Allocation memory allocation = allocator().getDepositAllocation(gauge(), assets);

        /// 3. Transfer the assets to the strategy from the account.
        for (uint256 i = 0; i < allocation.targets.length; i++) {
            SafeERC20.safeTransferFrom(IERC20(asset()), account, allocation.targets[i], allocation.amounts[i]);
        }

        /// 4. Deposit the assets into the strategy.
        uint256 pendingRewards = strategy().deposit(allocation);

        /// 5. Checkpoint the vault. The accountant will deal with minting and burning.
        _mint(receiver, shares, pendingRewards, allocation.claimRewards);

        /// 6. Emit the Deposit event.
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    //////////////////////////////////////////////////////
    /// --- WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////

    /// @notice Returns the maximum amount of assets that can be withdrawn by an owner
    /// @dev Maximum withdrawal is limited to the owner's balance
    /// @param owner The address to check withdrawal limit for
    /// @return The maximum amount of assets that can be withdrawn
    function maxWithdraw(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    /// @notice Returns the maximum amount of shares that can be redeemed by an owner
    /// @dev Maximum redemption is limited to the owner's balance
    /// @param owner The address to check redemption limit for
    /// @return The maximum amount of shares that can be redeemed
    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    /// @notice Simulates the amount of shares needed for a withdrawal
    /// @dev Uses 1:1 conversion ratio in this implementation
    /// @param assets The amount of assets to simulate withdrawal for
    /// @return The amount of shares that would be burned
    function previewWithdraw(uint256 assets) public pure returns (uint256) {
        return convertToShares(assets);
    }

    /// @notice Simulates the amount of assets that would be withdrawn for a redemption
    /// @dev Uses 1:1 conversion ratio in this implementation
    /// @param shares The amount of shares to simulate redemption for
    /// @return The amount of assets that would be returned
    function previewRedeem(uint256 shares) public pure returns (uint256) {
        return convertToAssets(shares);
    }

    /// @notice Withdraws assets from the vault to receiver by burning shares from owner
    /// @dev Handles allowance checks and withdrawal allocation through strategy
    /// @param assets The amount of assets to withdraw
    /// @param receiver The address to receive the assets
    /// @param owner The address to burn shares from
    /// @return assets The amount of assets withdrawn
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

    /// @notice Redeems shares from owner and sends assets to receiver
    /// @dev Handles allowance checks and withdrawal allocation through strategy
    /// @param shares The amount of shares to redeem
    /// @param receiver The address to receive the assets
    /// @param owner The address to burn shares from
    /// @return shares The amount of shares burned
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

    /// @notice Internal function to withdraw assets from the vault
    /// @dev Handles the actual withdrawal logic including strategy integration
    /// @param owner The account that owns the shares
    /// @param receiver The account receiving the assets
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of shares to burn
    function _withdraw(address owner, address receiver, uint256 assets, uint256 shares) internal virtual {
        /// 1. Update the reward state for the owner.
        _updateReward(owner, address(0));

        /// 2. Get the allocation.
        IAllocator.Allocation memory allocation = allocator().getWithdrawAllocation(gauge(), assets);

        /// 3. Withdraw the assets from the strategy.
        uint256 pendingRewards = strategy().withdraw(allocation);

        /// 4. Checkpoint the vault. The accountant will deal with minting and burning.
        _burn(owner, shares, pendingRewards, allocation.claimRewards);

        /// 5. Transfer the assets to the receiver.
        SafeERC20.safeTransfer(IERC20(asset()), receiver, shares);

        /// 6. Emit the Withdraw event.
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    //////////////////////////////////////////////////////
    /// --- REWARD LOGIC
    //////////////////////////////////////////////////////

    /// @notice Returns the rewards distributor for a given token
    /// @dev Extracts distributor address from packed storage
    /// @param token The reward token address
    /// @return The address of the rewards distributor
    function getRewardsDistributor(address token) public view returns (address) {
        return address(
            uint160(
                rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                    & StorageMasks.REWARD_DISTRIBUTOR
            )
        );
    }

    /// @notice Returns the rewards duration for a given token
    /// @dev Extracts duration from packed storage
    /// @param token The reward token address
    /// @return The duration in seconds
    function getRewardsDuration(address token) public view returns (uint32) {
        return uint32(
            (rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot & StorageMasks.REWARD_DURATION)
                >> 160
        );
    }

    /// @notice Returns the last update time for a given token
    /// @dev Extracts last update time from packed storage
    /// @param token The reward token address
    /// @return The timestamp of the last update
    function getLastUpdateTime(address token) public view returns (uint32) {
        return uint32(
            (rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot & StorageMasks.REWARD_LAST_UPDATE)
                >> 192
        );
    }

    /// @notice Returns the period finish time for a given token
    /// @dev Extracts period finish time from packed storage
    /// @param token The reward token address
    /// @return The timestamp when rewards end
    function getPeriodFinish(address token) public view returns (uint32) {
        return uint32(
            (
                rewardData[token].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                    & StorageMasks.REWARD_PERIOD_FINISH
            ) >> 224
        );
    }

    /// @notice Returns the reward rate for a given token
    /// @dev Extracts reward rate from packed storage
    /// @param token The reward token address
    /// @return The rewards per second rate
    function getRewardRate(address token) public view returns (uint128) {
        return uint128((rewardData[token].rewardRateAndRewardPerTokenStoredSlot & StorageMasks.REWARD_RATE) >> 128);
    }

    /// @notice Returns the reward per token stored for a given token
    /// @dev Extracts reward per token from packed storage
    /// @param token The reward token address
    /// @return The accumulated rewards per token
    function getRewardPerTokenStored(address token) public view returns (uint128) {
        return uint128(rewardData[token].rewardRateAndRewardPerTokenStoredSlot & StorageMasks.REWARD_PER_TOKEN_STORED);
    }

    /// @notice Returns the reward amount for the current duration
    /// @dev Calculates total rewards by multiplying rate by duration
    /// @param _rewardsToken The reward token to check
    /// @return The total rewards for the duration
    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return getRewardRate(_rewardsToken) * getRewardsDuration(_rewardsToken);
    }

    /// @notice Returns the last applicable time for reward calculation
    /// @dev Returns the earlier of current time or period finish
    /// @param _rewardsToken The reward token to check
    /// @return The minimum of current time and period finish
    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, getPeriodFinish(_rewardsToken));
    }

    /// @notice Calculates the current reward per token
    /// @dev Accounts for time elapsed since last update
    /// @param _rewardsToken The reward token to calculate for
    /// @return The current reward per token rate
    function rewardPerToken(address _rewardsToken) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return getRewardPerTokenStored(_rewardsToken);
        }
        return getRewardPerTokenStored(_rewardsToken)
            + (
                (lastTimeRewardApplicable(_rewardsToken) - getLastUpdateTime(_rewardsToken)) * getRewardRate(_rewardsToken)
                    * 1e18 / _totalSupply
            );
    }

    /// @notice Calculates the earned rewards for an account
    /// @dev Includes both stored and newly accumulated rewards
    /// @param account The account to calculate earnings for
    /// @param _rewardsToken The reward token to calculate
    /// @return The total earned rewards
    function earned(address account, address _rewardsToken) public view returns (uint256) {
        PackedAccount storage accountDataValue = accountData[account][_rewardsToken];
        uint256 rewardPerTokenPaid =
            accountDataValue.rewardPerTokenPaidAndClaimableSlot & StorageMasks.ACCOUNT_REWARD_PER_TOKEN;
        uint256 claimable =
            (accountDataValue.rewardPerTokenPaidAndClaimableSlot & StorageMasks.ACCOUNT_CLAIMABLE) >> 128;

        uint256 newEarned = balanceOf(account) * (rewardPerToken(_rewardsToken) - rewardPerTokenPaid) / 1e18;
        return claimable + newEarned;
    }

    /// @notice Updates reward state for an account
    /// @dev Updates reward accounting for a specific account
    /// @param account The account to update rewards for
    function updateReward(address account) external {
        _updateReward(account, address(0));
    }

    /// @notice Adds a new reward token to the vault
    /// @dev Initializes reward data with distributor and default 7-day duration
    /// @param _rewardsToken The address of the reward token to add
    /// @param _distributor The address authorized to distribute rewards
    function addRewardToken(address _rewardsToken, address _distributor) external {
        /// 1. Verify caller is authorized and token can be added
        require(registry().allowed(address(this), msg.sender, msg.sig), OnlyAllowed());
        require(!isRewardToken[_rewardsToken], RewardAlreadyExists());
        require(rewardTokens.length < MAX_REWARD_TOKEN_COUNT, MaxRewardTokensExceeded());

        /// 2. Add token to tracking arrays and mappings
        rewardTokens.push(_rewardsToken);
        isRewardToken[_rewardsToken] = true;

        /// 3. Pack and store reward data
        /// 3a. Set distributor address in lower 160 bits
        /// 3b. Set default 7-day duration in bits 160-191
        uint256 distributorAndDurationAndLastUpdateAndPeriodFinishSlot = (
            uint160(_distributor) & StorageMasks.REWARD_DISTRIBUTOR
        ) | ((uint256(7 days) << 160) & StorageMasks.REWARD_DURATION);

        /// 4. Update storage with packed data
        rewardData[_rewardsToken].distributorAndDurationAndLastUpdateAndPeriodFinishSlot =
            distributorAndDurationAndLastUpdateAndPeriodFinishSlot;

        /// 5. Emit event for new reward token
        emit RewardTokenAdded(_rewardsToken, _distributor);
    }

    /// @notice Deposits rewards into the vault
    /// @dev Handles reward rate updates and token transfers
    /// @param _rewardsToken The reward token being distributed
    /// @param _amount The amount of rewards to distribute
    function depositRewards(address _rewardsToken, uint256 _amount) external {
        /// 1. Update reward state for all tokens before modifying rates
        _updateReward(address(0), address(0));

        /// 2. Verify caller is authorized distributor for this reward token
        require(getRewardsDistributor(_rewardsToken) == msg.sender, UnauthorizedRewardsDistributor());

        /// 3. Transfer reward tokens from distributor to vault
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), _amount);

        /// 4. Cache current state values
        uint32 currentTime = uint32(block.timestamp);
        uint32 periodFinish = getPeriodFinish(_rewardsToken);
        uint32 rewardsDuration = getRewardsDuration(_rewardsToken);
        uint256 newRewardRate;

        /// 5. Calculate new reward rate based on timing
        if (currentTime >= periodFinish) {
            /// 5a. If previous period is finished, simply distribute new rewards over duration
            newRewardRate = _amount / rewardsDuration;
        } else {
            /// 5b. If previous period is still active, add remaining rewards to new amount
            uint256 remaining = periodFinish - currentTime;
            uint256 leftover = remaining * getRewardRate(_rewardsToken);
            newRewardRate = (_amount + leftover) / rewardsDuration;
        }

        /// 6. Ensure reward rate doesn't overflow uint128
        require(newRewardRate <= type(uint128).max, RewardRateOverflow());

        /// 7. Pack and update first storage slot (distributor, duration, timestamps)
        uint256 distributorAndDurationAndLastUpdateAndPeriodFinishSlot =
        /// 7a. Keep existing distributor address
        (
            rewardData[_rewardsToken].distributorAndDurationAndLastUpdateAndPeriodFinishSlot
                & StorageMasks.REWARD_DISTRIBUTOR
        )
        /// 7b. Update rewards duration
        | ((uint256(rewardsDuration) << 160) & StorageMasks.REWARD_DURATION)
        /// 7c. Set last update time to current
        | ((uint256(currentTime) << 192) & StorageMasks.REWARD_LAST_UPDATE)
        /// 7d. Set new period finish time
        | ((uint256(currentTime + rewardsDuration) << 224) & StorageMasks.REWARD_PERIOD_FINISH);

        /// 8. Pack and update second storage slot (reward rate and rewards per token)
        uint256 rewardRateAndRewardPerTokenStoredSlot =
        /// 8a. Keep existing rewards per token
        (getRewardPerTokenStored(_rewardsToken) & StorageMasks.REWARD_PER_TOKEN_STORED)
        /// 8b. Set new reward rate
        | ((uint256(newRewardRate) << 128) & StorageMasks.REWARD_RATE);

        /// 9. Update storage with new values (single SSTORE per slot)
        rewardData[_rewardsToken].distributorAndDurationAndLastUpdateAndPeriodFinishSlot =
            distributorAndDurationAndLastUpdateAndPeriodFinishSlot;
        rewardData[_rewardsToken].rewardRateAndRewardPerTokenStoredSlot = rewardRateAndRewardPerTokenStoredSlot;

        /// 10. Emit event with updated values
        emit RewardsDeposited(_rewardsToken, _amount, uint128(newRewardRate));
    }

    /// @notice Internal function to update reward state
    /// @dev Updates reward accounting for all tokens
    /// @param _from The account to update rewards for
    /// @param _to The account to update rewards for
    function _updateReward(address _from, address _to) internal {
        /// 1. Get total number of reward tokens and current timestamp
        uint256 len = rewardTokens.length;
        uint32 currentTime = uint32(block.timestamp);

        /// 2. Iterate through all reward tokens to update their state
        for (uint256 i; i < len; i++) {
            /// 2a. Get current token and its reward data
            address token = rewardTokens[i];

            uint256 newRewardPerToken = _updateRewardToken(token, currentTime);

            /// 7. Update account-specific data if account is provided
            if (_from != address(0)) {
                _updateAccountData(_from, token, newRewardPerToken);
            }

            /// 8. Update account-specific data if account is provided
            if (_to != address(0)) {
                _updateAccountData(_to, token, newRewardPerToken);
            }
        }
    }

    function _updateRewardToken(address token, uint32 currentTime) internal returns (uint256 newRewardPerToken) {
        PackedReward storage reward = rewardData[token];

        /// 2b. Cache storage values to minimize SLOADs
        uint256 distributorSlot = reward.distributorAndDurationAndLastUpdateAndPeriodFinishSlot;
        uint256 rateSlot = reward.rewardRateAndRewardPerTokenStoredSlot;

        /// 3. Calculate new reward per token based on time elapsed
        newRewardPerToken = rewardPerToken(token);

        /// 4. Pack updates for first storage slot (timestamps)
        /// 4a. Clear last update time bits while preserving other data
        /// 4b. Set new last update time in the cleared space
        distributorSlot = (distributorSlot & ~StorageMasks.REWARD_LAST_UPDATE)
            | ((uint256(currentTime) << 192) & StorageMasks.REWARD_LAST_UPDATE);

        /// 5. Pack updates for second storage slot (rates)
        /// 5a. Keep existing reward rate
        /// 5b. Update reward per token stored
        rateSlot =
            (rateSlot & StorageMasks.REWARD_RATE) | (uint128(newRewardPerToken) & StorageMasks.REWARD_PER_TOKEN_STORED);

        /// 6. Update storage with new values (single SSTORE per slot)
        reward.distributorAndDurationAndLastUpdateAndPeriodFinishSlot = distributorSlot;
        reward.rewardRateAndRewardPerTokenStoredSlot = rateSlot;
    }

    function _updateAccountData(address account, address token, uint256 newRewardPerToken) internal {
        /// 8a. Calculate earned rewards for account
        uint256 earnedAmount = earned(account, token);

        /// 8b. Pack and update account data in single SSTORE
        /// - Lower 128 bits: new reward per token paid
        /// - Upper 128 bits: earned amount
        accountData[account][token].rewardPerTokenPaidAndClaimableSlot = (
            uint128(newRewardPerToken) & StorageMasks.ACCOUNT_REWARD_PER_TOKEN
        ) | ((uint256(uint128(earnedAmount)) << 128) & StorageMasks.ACCOUNT_CLAIMABLE);
    }

    //////////////////////////////////////////////////////
    /// --- REGISTRY AND CLONE IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Returns the registry contract address from clone args
    /// @dev Retrieves registry address from immutable clone arguments
    /// @return _registry The IRegistry interface of the registry contract
    function registry() public view returns (IRegistry _registry) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _registry := mload(add(args, 20))
        }
    }

    /// @notice Returns the accountant contract address from clone args
    /// @dev Retrieves accountant address from immutable clone arguments
    /// @return _accountant The IAccountant interface of the accountant contract
    function accountant() public view returns (IAccountant _accountant) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _accountant := mload(add(args, 40))
        }
    }

    /// @notice Returns the gauge address from clone args
    /// @dev Retrieves gauge address from immutable clone arguments
    /// @return _gauge The address of the gauge contract
    function gauge() public view returns (address _gauge) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _gauge := mload(add(args, 60))
        }
    }

    /// @notice Returns the allocator contract from registry
    /// @dev Retrieves current allocator from registry
    /// @return _allocator The IAllocator interface of the allocator contract
    function allocator() public view returns (IAllocator _allocator) {
        return IAllocator(registry().allocator());
    }

    /// @notice Returns the strategy contract from registry
    /// @dev Retrieves current strategy from registry
    /// @return _strategy The IStrategy interface of the strategy contract
    function strategy() public view returns (IStrategy _strategy) {
        return IStrategy(registry().strategy());
    }

    //////////////////////////////////////////////////////
    /// --- ERC20 OVERRIDES
    //////////////////////////////////////////////////////

    /// @notice Used by ERC20 transfers to update balances and reward state.
    /// @dev Delegates balance updates to the accountant
    /// @param from The account to transfer from
    /// @param to The account to transfer to
    /// @param amount The amount of assets to transfer
    function _update(address from, address to, uint256 amount) internal override {
        /// 1. Update Balances.
        accountant().checkpoint(gauge(), from, to, amount, 0, false);

        /// 2. Update Reward State.
        /// @dev No need to check for zero address as the transfer function will handle it.
        _updateReward(from, to);

        /// 4. Emit the Transfer event.
        emit Transfer(from, to, amount);
    }

    /// @notice Internal function to mint shares to an account
    /// @dev Delegates minting to the accountant
    /// @param to The account to mint shares to
    /// @param amount The amount of shares to mint
    /// @param pendingRewards The amount of pending rewards to add
    /// @param harvested wether pendingRewards are claimed and available in the accountant
    function _mint(address to, uint256 amount, uint256 pendingRewards, bool harvested) internal {
        accountant().checkpoint(gauge(), address(0), to, amount, pendingRewards, harvested);
    }

    /// @notice Internal function to burn shares from an account
    /// @dev Delegates burning to the accountant
    /// @param from The account to burn shares from
    /// @param amount The amount of shares to burn
    /// @param pendingRewards The amount of pending rewards to subtract
    /// @param harvested wether pendingRewards are claimed and available in the accountant
    function _burn(address from, uint256 amount, uint256 pendingRewards, bool harvested) internal {
        accountant().checkpoint(gauge(), from, address(0), amount, pendingRewards, harvested);
    }

    /// @notice Returns the name of the vault token
    /// @dev Concatenates "StakeDAO" with the underlying asset name
    /// @return The name string including the underlying asset name
    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("StakeDAO ", IERC20Metadata(asset()).name(), " Vault");
    }

    /// @notice Returns the symbol of the vault token
    /// @dev Concatenates "sd-" with the underlying asset symbol
    /// @return The symbol string including the underlying asset symbol
    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("sd-", IERC20Metadata(asset()).symbol(), "-vault");
    }

    /// @notice Returns the number of decimals of the vault token
    /// @dev Matches the decimals of the underlying asset
    /// @return The number of decimals matching the underlying asset
    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }

    /// @notice Returns the total supply of vault shares
    /// @dev Delegates total supply tracking to the accountant
    /// @return The total supply from the accountant
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return accountant().totalSupply(address(this));
    }

    /// @notice Returns the balance of vault shares for an account
    /// @dev Delegates balance tracking to the accountant
    /// @param account The account to check the balance for
    /// @return The balance from the accountant
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return accountant().balanceOf(address(this), account);
    }
}
