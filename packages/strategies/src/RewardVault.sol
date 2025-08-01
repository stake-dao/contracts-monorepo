// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, IERC20Metadata, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {ImmutableArgsParser} from "src/libraries/ImmutableArgsParser.sol";

/// @title RewardVault.
/// @author Stake DAO
/// @custom:github @stake-dao
/// @custom:contact contact@stakedao.org

/// @notice RewardVault is the user-facing ERC4626 vault for yield aggregation, serving as the entry point
///         for users to deposit LP tokens and earn rewards. It manages extra reward tokens from gauges
///         (e.g., LDO, BAL) while main protocol rewards (CRV) are handled by the Accountant. The vault
///         routes deposits and withdrawals through the Strategy and Allocator, maintaining full ERC4626
///         compliance for composability.
contract RewardVault is IRewardVault, IERC4626, ERC20 {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using ImmutableArgsParser for address;
    ///////////////////////////////////////////////////////////////
    // --- EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when a new reward token is added to the vault
    /// @param rewardToken The address of the reward token being added
    /// @param distributor The authorized address that can distribute this reward
    event RewardTokenAdded(address indexed rewardToken, address indexed distributor);

    /// @notice Emitted when new rewards are deposited for distribution
    /// @param rewardToken The token being distributed as rewards
    /// @param amount The total amount of rewards being added
    /// @param rewardRate The calculated rate at which rewards will be distributed (tokens/second)
    event RewardsDeposited(address indexed rewardToken, uint256 amount, uint128 rewardRate);

    /// @notice Emitted when the vault resumes operations
    event OperationsResumed();

    ///////////////////////////////////////////////////////////////
    // --- ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Thrown when an operation is attempted by an unauthorized caller
    error NotApproved();

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();

    /// @notice Thrown when a function is called by an address not in the allowed list
    error OnlyAllowed();

    /// @notice Thrown when a function is called by an address that isn't a registrar
    error OnlyRegistrar();

    /// @notice Thrown when a function is called by an address that isn't the protocol controller
    error OnlyProtocolController();

    /// @notice Thrown when a protocol ID is zero
    error InvalidProtocolId();

    /// @notice Thrown when attempting to allocate assets to an unapproved target
    error TargetNotApproved();

    /// @notice Thrown when attempting to interact with an unregistered reward token
    error InvalidRewardToken();

    /// @notice Thrown when attempting to add a reward token that's already registered
    error RewardAlreadyExists();

    /// @notice Thrown when an unauthorized address attempts to distribute rewards
    error UnauthorizedRewardsDistributor();

    ///////////////////////////////////////////////////////////////
    // --- CONSTANTS & IMMUTABLES
    ///////////////////////////////////////////////////////////////

    /// @notice Default duration for reward distribution periods
    uint32 public constant DEFAULT_REWARDS_DURATION = 7 days;

    /// @notice Protocol identifier (e.g., bytes4(keccak256("CURVE")))
    bytes4 public immutable PROTOCOL_ID;

    /// @notice Accountant tracks user balances and main protocol rewards
    IAccountant public immutable ACCOUNTANT;

    /// @notice Central registry for strategies, allocators, and permissions
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    /// @notice Determines reward claiming behavior during user actions
    /// @dev HARVEST = claim on every action, CHECKPOINT = accumulate until manual harvest
    IStrategy.HarvestPolicy public immutable POLICY;

    ///////////////////////////////////////////////////////////////
    // --- STORAGE STRUCTURES
    ///////////////////////////////////////////////////////////////

    /// @notice Tracks distribution parameters for each extra reward token
    /// @dev Packed into 2 storage slots for gas efficiency
    struct RewardData {
        // Slot 1
        address rewardsDistributor; // Who can add rewards for this token
        uint32 lastUpdateTime; // Last time rewardPerTokenStored was updated
        uint32 periodFinish; // When current reward period ends
        // Slot 2
        uint128 rewardRate; // Tokens distributed per second
        uint128 rewardPerTokenStored; // Cumulative rewards per vault token (scaled by 1e18)
    }

    /// @notice Tracks user's reward state for each reward token
    /// @dev Packed into 1 storage slot
    struct AccountData {
        uint128 rewardPerTokenPaid; // User's last synced rewardPerTokenStored
        uint128 claimable; // Rewards ready to claim
    }

    ///////////////////////////////////////////////////////////////
    // --- STATE VARIABLES
    ///////////////////////////////////////////////////////////////

    /// @notice List of extra reward tokens this vault distributes
    address[] internal rewardTokens;

    /// @notice Distribution parameters for each reward token
    mapping(address rewardToken => RewardData rewardData) public rewardData;

    /// @notice User reward accounting per token
    mapping(address account => mapping(address rewardToken => AccountData accountData)) public accountData;

    ///////////////////////////////////////////////////////////////
    // --- MODIFIERS
    ///////////////////////////////////////////////////////////////

    /// @notice Restricts functions to the protocol controller
    modifier onlyProtocolController() {
        require(msg.sender == address(PROTOCOL_CONTROLLER), OnlyProtocolController());

        _;
    }

    /// @notice Restricts functions to addresses with specific permissions
    modifier onlyAllowed() {
        require(PROTOCOL_CONTROLLER.allowed(address(this), msg.sender, msg.sig), OnlyAllowed());

        _;
    }

    /// @notice Restricts functions to authorized vault deployers
    modifier onlyRegistrar() {
        require(PROTOCOL_CONTROLLER.isRegistrar(msg.sender), OnlyRegistrar());

        _;
    }

    /// @notice Initializes the vault with basic ERC20 metadata
    /// @dev Sets up the vault with a standard name and symbol prefix
    /// @param protocolId The protocol ID.
    /// @param protocolController The protocol controller address
    /// @param accountant The accountant address
    /// @param policy The harvest policy.
    /// @custom:reverts ZeroAddress if the accountant or protocol controller address is the zero address.
    constructor(bytes4 protocolId, address protocolController, address accountant, IStrategy.HarvestPolicy policy)
        ERC20("", "")
    {
        require(accountant != address(0) && protocolController != address(0), ZeroAddress());
        require(protocolId != bytes4(0), InvalidProtocolId());

        PROTOCOL_ID = protocolId;
        ACCOUNTANT = IAccountant(accountant);
        PROTOCOL_CONTROLLER = IProtocolController(protocolController);
        POLICY = policy;
    }

    ///////////////////////////////////////////////////////////////
    // --- DEPOSIT & MINT - PUBLIC
    ///////////////////////////////////////////////////////////////

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        return deposit(assets, receiver, address(0));
    }

    /// @notice Deposits LP tokens and mints vault shares
    /// @dev Allocator determines where to send the LP tokens (locker, sidecar, etc.)
    /// @param assets Amount of LP tokens to deposit
    /// @param receiver Address to receive vault shares (defaults to msg.sender if zero)
    /// @param referrer Optional referrer for tracking (emitted in Accountant event)
    /// @return _ Amount deposited (always equals assets due to 1:1 ratio)
    function deposit(uint256 assets, address receiver, address referrer) public returns (uint256) {
        if (receiver == address(0)) receiver = msg.sender;

        _deposit(msg.sender, receiver, assets, assets, referrer);

        return assets;
    }

    /// @notice Mints exact `shares` to `receiver` by depositing assets.
    /// @dev Due to the 1:1 relationship between the assets and the shares,
    ///      the mint function is a wrapper of the deposit function.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address to receive the minted shares.
    /// @param referrer The address of the referrer. Can be the zero address.
    /// @return _ The amount of shares minted.
    function mint(uint256 shares, address receiver, address referrer) external returns (uint256) {
        return deposit(shares, receiver, referrer);
    }

    /// @notice Mints exact `shares` to `receiver` by depositing assets.
    /// @dev Due to the 1:1 relationship between the assets and the shares,
    ///      the mint function is a wrapper of the deposit function.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address to receive the minted shares.
    /// @return _ The amount of shares minted.
    function mint(uint256 shares, address receiver) external returns (uint256) {
        return deposit(shares, receiver, address(0));
    }

    ///////////////////////////////////////////////////////////////
    // --- DEPOSIT & MINT - PERMISSIONED
    ///////////////////////////////////////////////////////////////

    /// @notice Deposits `assets` from `account` into the vault and mints shares to `account`.
    /// @dev Only callable by allowed addresses. `account` should have approved this contract to transfer `assets`.
    ///      This function tracks the referrer address and handles deposit allocation through strategy and updates rewards.
    /// @param account The address to deposit assets from and mint shares to.
    /// @param receiver The address to receive the minted shares.
    /// @param assets The amount of assets to deposit.
    /// @param referrer The address of the referrer. Can be the zero address.
    /// @return _ The amount of assets deposited.
    /// @custom:reverts ZeroAddress if the account or receiver address is the zero address.
    function deposit(address account, address receiver, uint256 assets, address referrer)
        public
        onlyAllowed
        returns (uint256)
    {
        require(account != address(0) && receiver != address(0), ZeroAddress());

        _deposit(account, receiver, assets, assets, referrer);

        // return the amount of assets deposited. Thanks to the 1:1 relationship between assets and shares
        // the amount of assets deposited is the same as the amount of shares minted
        return assets;
    }

    ///////////////////////////////////////////////////////////////
    /// ~ DEPOSIT - INTERNAL
    ///////////////////////////////////////////////////////////////

    /// @dev Internal function to deposit assets into the vault.
    ///      1. Update the reward state for the receiver.
    ///      2. Get the deposit allocation.
    ///      3. Transfer assets to the targets.
    ///      4. Trigger deposit on the strategy.
    ///      5. Mint shares (accountant checkpoint).
    ///      6. Emit Deposit event.
    /// @param account The address of the account to deposit assets from.
    /// @param receiver The address to receive the minted shares.
    /// @param assets The amount of assets to deposit.
    /// @param shares The amount of shares to mint.
    /// @param referrer The address of the referrer. Can be the zero address.
    function _deposit(address account, address receiver, uint256 assets, uint256 shares, address referrer) internal {
        _deposit(account, receiver, assets, shares, referrer, false);
    }

    /// @dev Internal function to deposit assets into the vault with transfer mode option.
    /// @param account The address of the account to deposit assets from.
    /// @param receiver The address to receive the minted shares.
    /// @param assets The amount of assets to deposit.
    /// @param shares The amount of shares to mint.
    /// @param referrer The address of the referrer. Can be the zero address.
    /// @param useTransfer True to use safeTransfer (for resumeVault), false for safeTransferFrom
    function _deposit(
        address account,
        address receiver,
        uint256 assets,
        uint256 shares,
        address referrer,
        bool useTransfer
    ) internal {
        // 1. Update extra reward state before balance changes
        if (receiver != address(0)) {
            _checkpoint(receiver, address(0));
        }

        // Allocate funds to targets and deposit through strategy
        IStrategy.PendingRewards memory pendingRewards = _allocateFunds(account, assets, useTransfer);

        // Update Accountant balances and mint shares
        _mint(receiver, shares, pendingRewards, POLICY, referrer);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @dev Allocates funds to targets and deposits through strategy
    /// @param from Source of assets (user address or address(this) for resumeVault)
    /// @param assets Amount to allocate
    /// @param useTransfer True to use safeTransfer (resumeVault), false for safeTransferFrom (deposits)
    /// @return pendingRewards Rewards harvested during deposit
    function _allocateFunds(address from, uint256 assets, bool useTransfer)
        internal
        returns (IStrategy.PendingRewards memory pendingRewards)
    {
        // Ask allocator where to send the LP tokens (e.g., 70% locker, 30% Convex)
        IAllocator.Allocation memory allocation = allocator().getDepositAllocation(asset(), gauge(), assets);

        // Transfer LP tokens directly to allocation targets (bypasses vault)
        IERC20 _asset = IERC20(asset());
        for (uint256 i; i < allocation.targets.length; i++) {
            if (allocation.amounts[i] == 0) continue;
            require(PROTOCOL_CONTROLLER.isValidAllocationTarget(gauge(), allocation.targets[i]), TargetNotApproved());

            if (useTransfer) {
                SafeERC20.safeTransfer(_asset, allocation.targets[i], allocation.amounts[i]);
            } else {
                SafeERC20.safeTransferFrom(_asset, from, allocation.targets[i], allocation.amounts[i]);
            }
        }

        // Strategy deposits into gauge/sidecar and may harvest if HARVEST policy
        return strategy().deposit(allocation, POLICY);
    }

    ///////////////////////////////////////////////////////////////
    // --- EXTERNAL/PUBLIC USER-FACING - WITHDRAW & REDEEM
    ///////////////////////////////////////////////////////////////

    /// @notice Burns vault shares and returns LP tokens to receiver
    /// @dev Strategy handles withdrawing from gauge and sending tokens to receiver
    /// @param assets Amount of LP tokens to withdraw
    /// @param receiver Address to receive LP tokens (defaults to msg.sender if zero)
    /// @param owner Address whose shares will be burned
    /// @return _ Amount withdrawn (always equals assets due to 1:1 ratio)
    /// @custom:reverts NotApproved if caller lacks sufficient allowance
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256) {
        if (receiver == address(0)) receiver = msg.sender;

        // if the caller isn't the owner, check if the caller is allowed to withdraw the amount of assets
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            require(assets <= allowed, NotApproved());
            if (allowed != type(uint256).max) _spendAllowance(owner, msg.sender, assets);
        }

        _withdraw(owner, receiver, assets, assets);

        // return the amount of assets withdrawn. Thanks to the 1:1 relationship between assets and shares
        // the amount of assets withdrawn is the same as the amount of shares burned
        return assets;
    }

    /// @notice Redeems `shares` from `owner` and sends assets to `receiver`.
    /// @dev Checks allowances and calls strategy withdrawal logic. Due to the 1:1
    ///      relationship of the assets and the shares, the redeem function is a
    ///      wrapper of the withdraw function.
    /// @param shares The amount of shares to redeem.
    /// @param receiver The address to receive the assets.
    /// @param owner The address to burn shares from.
    /// @return _ The amount of shares burned.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        return withdraw(shares, receiver, owner);
    }

    /// @dev Internal function to withdraw assets from the vault.
    function _withdraw(address owner, address receiver, uint256 assets, uint256 shares) internal {
        // Update the reward state for the owner.
        _checkpoint(owner, address(0));

        // Get the address of the allocator contract from the protocol controller
        // then fetch the withdrawal allocation from the allocator
        IAllocator.Allocation memory allocation = allocator().getWithdrawalAllocation(asset(), gauge(), assets);

        // Get the address of the strategy contract from the protocol controller
        // then process the withdrawal of the allocation
        IStrategy.PendingRewards memory pendingRewards = strategy().withdraw(allocation, POLICY, receiver);

        // Burn the shares by calling the endpoint function of the accountant contract
        _burn(owner, shares, pendingRewards, POLICY);

        /// @dev If the gauge is shutdown, funds will sit here pending recovery
        /// @dev Recovery mechanism: users can withdraw directly from vault
        if (PROTOCOL_CONTROLLER.isShutdown(gauge())) {
            // Transfer the assets to the receiver. The 1:1 relationship between assets and shares is maintained.
            SafeERC20.safeTransfer(IERC20(asset()), receiver, shares);
        }

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    ///////////////////////////////////////////////////////////////
    // --- EMERGENCY -
    ///////////////////////////////////////////////////////////////

    /// @notice Resumes the vault operations
    /// @dev Only callable by the protocol controller
    /// @custom:reverts OnlyProtocolController if caller is not the protocol controller
    function resumeVault() external onlyProtocolController {
        uint256 assets = _safeTotalSupply();

        // If there are no assets in the vault, we don't need to do anything
        if (assets == 0) {
            emit OperationsResumed();
            return;
        }

        // Use internal deposit function with vault as both source and receiver
        // No new shares are minted (amount = 0) since we're just re-depositing existing assets
        _deposit({
            account: address(0),
            receiver: address(0),
            assets: assets,
            shares: 0,
            referrer: address(0),
            useTransfer: true
        });

        emit OperationsResumed();
    }

    ///////////////////////////////////////////////////////////////
    // --- EXTERNAL/PUBLIC USER-FACING - REWARDS
    ///////////////////////////////////////////////////////////////

    /// @notice Claims rewards for multiple tokens in a single transaction
    /// @dev Updates reward state and transfers claimed rewards to the receiver
    /// @param tokens Array of reward token addresses to claim
    /// @param receiver Address to receive the claimed rewards (defaults to msg.sender if zero)
    /// @return amounts Array of amounts claimed for each token, in the same order as input tokens
    function claim(address[] calldata tokens, address receiver) public returns (uint256[] memory amounts) {
        return _claim(msg.sender, tokens, receiver);
    }

    /// @notice Claims rewards on behalf of another account (requires authorization)
    /// @dev Only callable by addresses allowed by the protocol controller
    /// @param account Address to claim rewards for
    /// @param tokens Array of reward token addresses to claim
    /// @param receiver Address to receive the claimed rewards
    /// @return amounts Array of amounts claimed for each token
    /// @custom:reverts OnlyAllowed if caller is not authorized
    function claim(address account, address[] calldata tokens, address receiver)
        public
        onlyAllowed
        returns (uint256[] memory amounts)
    {
        return _claim(account, tokens, receiver);
    }

    /// @dev Core reward claiming implementation
    /// @param account Account whose rewards are being claimed
    /// @param tokens Array of reward tokens to process
    /// @param receiver Destination for the claimed rewards
    /// @return amounts Array of claimed amounts per token
    /// @custom:reverts InvalidRewardToken if any token is not registered
    function _claim(address account, address[] calldata tokens, address receiver)
        internal
        returns (uint256[] memory amounts)
    {
        if (receiver == address(0)) receiver = account;

        // Update all reward states before processing claims
        _checkpoint(account, address(0));

        amounts = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            address rewardToken = tokens[i];
            require(isRewardToken(rewardToken), InvalidRewardToken());

            // Calculate earned rewards since last claim
            AccountData storage accountData_ = accountData[account][rewardToken];
            uint256 accountEarned = accountData_.claimable;
            if (accountEarned == 0) continue;

            // Reset claimable amount
            accountData_.claimable = 0;

            // Transfer earned rewards to receiver
            SafeERC20.safeTransfer(IERC20(rewardToken), receiver, accountEarned);
            amounts[i] = accountEarned;
        }
        return amounts;
    }

    /// @notice Registers a new extra reward token for this vault
    /// @dev Called by factory during vault deployment to setup gauge rewards
    /// @param rewardToken Address of the extra reward token (e.g., LDO, BAL)
    /// @param distributor Address that receives and distributes these rewards
    /// @custom:reverts OnlyRegistrar if caller is not a registrar
    /// @custom:reverts ZeroAddress if distributor is zero address
    /// @custom:reverts RewardAlreadyExists if token is already registered
    function addRewardToken(address rewardToken, address distributor) external onlyRegistrar {
        require(distributor != address(0), ZeroAddress());

        RewardData storage reward = rewardData[rewardToken];
        require(!_isRewardToken(reward), RewardAlreadyExists());

        rewardTokens.push(rewardToken);
        reward.rewardsDistributor = distributor;

        emit RewardTokenAdded(rewardToken, distributor);
    }

    /// @notice Deposits rewards for linear distribution over 7 days
    /// @dev Automatically handles rollover of undistributed rewards
    /// @param rewardToken Token to distribute (must be pre-registered)
    /// @param amount Amount to distribute over the next period
    /// @custom:reverts UnauthorizedRewardsDistributor if caller isn't the distributor
    function depositRewards(address rewardToken, uint128 amount) external {
        // Ensure all reward states are current
        _checkpoint(address(0), address(0));

        RewardData storage reward = rewardData[rewardToken];
        require(reward.rewardsDistributor == msg.sender, UnauthorizedRewardsDistributor());

        uint32 currentTime = uint32(block.timestamp);
        uint32 periodFinish = reward.periodFinish;
        uint128 newRewardRate;

        // Calculate new reward rate, accounting for any remaining rewards
        if (currentTime >= periodFinish) {
            newRewardRate = Math.mulDiv(amount, 1e18, DEFAULT_REWARDS_DURATION).toUint128();
        } else {
            uint32 remainingTime = periodFinish - currentTime;
            uint256 remainingRewardsUnscaled = Math.mulDiv(reward.rewardRate, remainingTime, 1e18);
            newRewardRate = Math.mulDiv(amount + remainingRewardsUnscaled, 1e18, DEFAULT_REWARDS_DURATION).toUint128();
        }

        // Update reward distribution state
        reward.lastUpdateTime = currentTime;
        reward.periodFinish = currentTime + DEFAULT_REWARDS_DURATION;
        reward.rewardRate = newRewardRate;

        // Transfer rewards to vault
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);

        emit RewardsDeposited(rewardToken, amount, newRewardRate);
    }

    /// @notice Manually updates reward accounting for an account
    /// @param account Account to update rewards for
    function checkpoint(address account) external {
        _checkpoint(account, address(0));
    }

    ///////////////////////////////////////////////////////////////
    // --- INTERNAL REWARD UPDATES & HELPERS ~
    ///////////////////////////////////////////////////////////////

    /// @notice Syncs extra reward accounting for affected accounts
    /// @dev Called before any balance change to ensure accurate reward distribution
    /// @param _from Account losing balance (address(0) to skip)
    /// @param _to Account gaining balance (address(0) to skip)
    function _checkpoint(address _from, address _to) internal {
        uint256 len = rewardTokens.length;

        for (uint256 i; i < len; i++) {
            address token = rewardTokens[i];
            uint128 newRewardPerToken = _updateRewardToken(token);

            if (_from != address(0)) {
                _updateAccountData(_from, token, newRewardPerToken);
            }
            if (_to != address(0)) {
                _updateAccountData(_to, token, newRewardPerToken);
            }
        }
    }

    /// @notice Updates the reward state for a specific token
    /// @dev Calculates and stores new reward per token value
    /// @param token The reward token to update
    /// @return newRewardPerToken The newly calculated reward per token value
    function _updateRewardToken(address token) internal returns (uint128 newRewardPerToken) {
        RewardData storage reward = rewardData[token];
        newRewardPerToken = _rewardPerToken(reward);
        reward.lastUpdateTime = _lastTimeRewardApplicable(reward.periodFinish);
        reward.rewardPerTokenStored = newRewardPerToken;
    }

    /// @notice Updates an account's reward data for a specific token
    /// @dev Calculates and stores earned rewards since last update
    /// @param account The account to update
    /// @param token The reward token to process
    /// @param newRewardPerToken Current reward per token value
    function _updateAccountData(address account, address token, uint128 newRewardPerToken) internal {
        AccountData storage accountData_ = accountData[account][token];
        accountData_.claimable = _earned(account, token, accountData_.claimable, accountData_.rewardPerTokenPaid);
        accountData_.rewardPerTokenPaid = newRewardPerToken;
    }

    /// @notice Checks if a reward token is properly registered
    /// @dev A token is considered registered if it has a non-zero distributor
    /// @param reward Storage pointer to the reward data
    /// @return True if the reward token is registered
    function _isRewardToken(RewardData storage reward) internal view returns (bool) {
        return reward.rewardsDistributor != address(0);
    }

    /// @notice Calculates the latest timestamp for reward distribution
    /// @dev Returns the earlier of current time or period finish
    /// @param periodFinish The timestamp when the reward period ends
    /// @return The latest timestamp for reward calculations
    function _lastTimeRewardApplicable(uint32 periodFinish) internal view returns (uint32) {
        return Math.min(block.timestamp, periodFinish).toUint32();
    }

    /// @notice Calculates the current reward per token value
    /// @dev Accounts for time elapsed and total supply
    /// @param reward Storage pointer to the reward data
    /// @return Current reward per token, scaled by 1e18
    function _rewardPerToken(RewardData storage reward) internal view returns (uint128) {
        uint128 _totalSupply = _safeTotalSupply();

        if (_totalSupply == 0) return reward.rewardPerTokenStored;

        uint256 timeDelta = _lastTimeRewardApplicable(reward.periodFinish) - reward.lastUpdateTime;
        uint256 rewardRatePerToken = 0;

        if (timeDelta > 0) {
            // Calculate additional rewards per token since last update
            rewardRatePerToken = Math.mulDiv(timeDelta, reward.rewardRate, _totalSupply);
        }

        return (reward.rewardPerTokenStored + rewardRatePerToken).toUint128();
    }

    /// @notice Calculates earned rewards for an account
    /// @dev Includes both stored claimable amount and newly earned rewards
    /// @param account The account to calculate rewards for
    /// @param token The reward token to calculate
    /// @param userClaimable Previously stored claimable amount
    /// @param userRewardPerTokenPaid Last checkpoint of reward per token for user
    /// @return Total earned rewards as uint128
    function _earned(address account, address token, uint128 userClaimable, uint128 userRewardPerTokenPaid)
        internal
        view
        returns (uint128)
    {
        uint128 newEarned = balanceOf(account).mulDiv(rewardPerToken(token) - userRewardPerTokenPaid, 1e18).toUint128();

        return userClaimable + newEarned;
    }

    ///////////////////////////////////////////////////////////////
    // --- VIEW / PURE METHODS ~
    ///////////////////////////////////////////////////////////////

    /// @notice Checks if a reward token exists.
    /// @dev The check is based on the assumption that the distributor is always set for a
    ///      active address and it can not be zero.
    /// @param rewardToken The address of the reward token to check.
    /// @return _ True if the reward token exists, false otherwise.
    function isRewardToken(address rewardToken) public view returns (bool) {
        RewardData storage reward = rewardData[rewardToken];

        return _isRewardToken(reward);
    }

    /// @notice Returns the address of the underlying token.
    /// @dev Retrieves the token address from the clone's immutable args.
    /// @return _ The address of the underlying token used by the vault.
    function asset() public view returns (address) {
        return address(this).readAddress(20);
    }

    /// @notice Returns the total amount of underlying assets (1:1 with total shares).
    /// @dev Due to the 1:1 relationship between assets and shares, the total assets
    ///      is the same as the total supply.
    /// @return _ The total amount of underlying assets.
    function totalAssets() external view returns (uint256) {
        return totalSupply();
    }

    /// @notice Converts a given number of assets to the equivalent amount of shares (1:1).
    /// @dev Due to the 1:1 relationship between assets and shares, the conversion is the same.
    /// @param assets The amount of assets to convert to shares.
    /// @return _ The amount of shares that would be received for the given amount of assets.
    ///           Basically the same value as the assets parameter.
    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /// @notice Converts a given number of shares to the equivalent amount of assets (1:1).
    /// @dev Due to the 1:1 relationship between assets and shares, the conversion is the same.
    /// @param shares The amount of shares to convert to assets.
    /// @return _ The amount of assets that would be received for the given amount of shares.
    ///           Basically the same value as the shares parameter.
    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    /// @notice Returns the amount of assets that would be received for a given amount of shares.
    /// @dev Due to the 1:1 relationship between assets and shares, the amount of assets
    ///      received is the same as the amount of shares deposited.
    /// @param shares The amount of shares to deposit.
    /// @return _ The amount of assets that would be received for the given amount of shares.
    ///           Basically the same value as the shares parameter.
    function previewDeposit(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    /// @notice Returns the amount of shares that would be received for a given amount of assets.
    /// @dev Due to the 1:1 relationship between assets and shares, the amount of shares
    ///      received is the same as the amount of assets deposited.
    /// @param assets The amount of assets to mint.
    /// @return _ The amount of shares that would be received for the given amount of assets.
    ///           Basically the same value as the assets parameter.
    function previewMint(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /// @notice Returns the amount of shares that would be received for a given amount of assets.
    /// @dev Due to the 1:1 relationship between assets and shares, the amount of shares
    ///      received is the same as the amount of assets withdrawn.
    /// @param assets The amount of assets to withdraw.
    /// @return _ The amount of shares that would be received for the given amount of assets.
    ///           Basically the same value as the assets parameter.
    function previewWithdraw(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    /// @notice Returns the amount of assets that would be received for a given amount of shares.
    /// @dev Due to the 1:1 relationship between assets and shares, the amount of tokens
    ///      received is the same as the amount of shares redeemed.
    /// @param shares The amount of shares to redeem.
    /// @return _ The amount of assets that would be received for the given amount of shares.
    ///           Basically the same value as the shares parameter.
    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    /// @notice Returns the maximum amount of assets that can be deposited.
    /// @dev The parameter is not used and is included to satisfy the interface. Pass whatever you want to.
    /// @return _ The maximum amount of assets that can be deposited.
    function maxDeposit(address) public pure returns (uint256) {
        return type(uint128).max;
    }

    /// @notice Returns the maximum amount of shares that can be minted.
    /// @dev Due to the 1:1 relationship between assets and shares, the max mint
    ///      is the same as the max deposit.
    /// @param _account The address of the account to calculate the max mint for.
    /// @return _ The maximum amount of shares that can be minted.
    function maxMint(address _account) external pure returns (uint256) {
        return maxDeposit(_account);
    }

    /// @notice Returns the maximum amount of assets that can be withdrawn.
    /// @param owner The address of the owner to calculate the max withdraw for.
    /// @return _ The maximum amount of assets that can be withdrawn.
    function maxWithdraw(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    /// @notice Returns the maximum amount of shares that can be redeemed.
    /// @dev Due to the 1:1 relationship between assets and shares, the max redeem
    ///      is the same as the max withdraw.
    /// @param owner The address of the owner to calculate the max redeem for.
    /// @return _ The maximum amount of shares that can be redeemed.
    function maxRedeem(address owner) external view returns (uint256) {
        return maxWithdraw(owner);
    }

    /// @notice Returns the distributor address for a given reward token.
    /// @param token The address of the reward token to calculate the distributor address for.
    /// @return _ The distributor address for the given reward token.
    function getRewardsDistributor(address token) external view returns (address) {
        return rewardData[token].rewardsDistributor;
    }

    /// @notice Returns the last update time for a given reward token.
    /// @param token The address of the reward token to calculate the last update time for.
    /// @return _ The last update time for the given reward token.
    function getLastUpdateTime(address token) external view returns (uint32) {
        return rewardData[token].lastUpdateTime;
    }

    /// @notice Returns the period finish time for a given reward token.
    /// @param token The address of the reward token to calculate the period finish time for.
    /// @return _ The period finish time for the given reward token.
    function getPeriodFinish(address token) external view returns (uint32) {
        return rewardData[token].periodFinish;
    }

    /// @notice Returns the reward rate for a given reward token.
    /// @param token The address of the reward token to calculate the reward rate for.
    /// @return _ The reward rate for the given reward token.
    function getRewardRate(address token) external view returns (uint128) {
        return rewardData[token].rewardRate;
    }

    /// @notice Returns the reward per token stored for a given reward token.
    /// @param token The address of the reward token to calculate the reward per token stored for.
    /// @return _ The reward per token stored for the given reward token.
    function getRewardPerTokenStored(address token) external view returns (uint128) {
        return rewardData[token].rewardPerTokenStored;
    }

    /// @notice Returns the reward per token paid for a given reward token and account.
    /// @param token The address of the reward token to calculate the reward per token paid for.
    /// @param account The address of the account to calculate the reward per token paid for.
    /// @return _ The reward per token paid for the given reward token and account.
    function getRewardPerTokenPaid(address token, address account) external view returns (uint128) {
        return accountData[account][token].rewardPerTokenPaid;
    }

    /// @notice Returns the claimable amount for a given reward token and account.
    /// @param token The address of the reward token to calculate the claimable amount for.
    /// @param account The address of the account to calculate the claimable amount for.
    /// @return _ The claimable amount for the given reward token and account.
    function getClaimable(address token, address account) external view returns (uint128) {
        return accountData[account][token].claimable;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    /// @notice Returns the total supply of this vault fetched from the accountant contract.
    /// @return _ The total supply of this vault.
    function totalSupply() public view override(ERC20, IERC20) returns (uint256) {
        return ACCOUNTANT.totalSupply(address(this));
    }

    /// @notice Returns the total supply of the vault safely casted as a uint128.
    /// @return _ The total supply of the vault safely casted as a uint128.
    /// @custom:reverts Overflow if the total supply is greater than the maximum value of a uint128.
    function _safeTotalSupply() internal view returns (uint128) {
        return totalSupply().toUint128();
    }

    /// @notice Returns the balance of the vault for a given account.
    /// @param account The address of the account to calculate the balance for.
    /// @return _ The balance of the vault for the given account.
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return ACCOUNTANT.balanceOf(address(this), account);
    }

    /// @notice Returns the last time reward is applicable for a given reward token
    /// @dev Wrapper around internal _lastTimeRewardApplicable function
    /// @param token The reward token to check
    /// @return Latest applicable timestamp for rewards
    function lastTimeRewardApplicable(address token) external view returns (uint256) {
        return _lastTimeRewardApplicable(rewardData[token].periodFinish);
    }

    /// @notice Returns the reward per token for a given reward token
    /// @dev Wrapper around internal _rewardPerToken function
    /// @param token The reward token to calculate for
    /// @return Current reward per token value
    function rewardPerToken(address token) public view returns (uint128) {
        return _rewardPerToken(rewardData[token]);
    }

    /// @notice Calculates total earned rewards for an account
    /// @dev Includes both claimed and pending rewards
    /// @param account Account to check rewards for
    /// @param token Reward token to calculate
    /// @return Total earned rewards
    function earned(address account, address token) external view returns (uint128) {
        AccountData storage accountData_ = accountData[account][token];
        return _earned(account, token, accountData_.claimable, accountData_.rewardPerTokenPaid);
    }

    ///////////////////////////////////////////////////////////////
    // --- PROTOCOL_CONTROLLER / CLONE ARGUMENT GETTERS ~
    ///////////////////////////////////////////////////////////////

    /// @notice Retrieves the gauge address from clone arguments
    /// @dev Uses assembly to read from clone initialization data
    /// @return _gauge The gauge contract address
    /// @custom:reverts CloneArgsNotFound if clone is incorrectly initialized
    function gauge() public view returns (address _gauge) {
        return address(this).readAddress(0);
    }

    /// @notice Gets the allocator contract for this protocol type
    /// @dev Fetches from protocol controller using PROTOCOL_ID
    /// @return _allocator The allocator contract interface
    function allocator() public view returns (IAllocator _allocator) {
        return IAllocator(PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID));
    }

    /// @notice Gets the strategy contract for this protocol type
    /// @dev Fetches from protocol controller using PROTOCOL_ID
    /// @return _strategy The strategy contract interface
    function strategy() public view returns (IStrategy _strategy) {
        return IStrategy(PROTOCOL_CONTROLLER.strategy(PROTOCOL_ID));
    }

    ///////////////////////////////////////////////////////////////
    // --- ERC20 OVERRIDES ~
    ///////////////////////////////////////////////////////////////

    /// @notice Handles reward state updates during token transfers
    /// @dev Updates balances via Accountant and reward states
    /// @param from Address sending tokens
    /// @param to Address receiving tokens
    /// @param amount Number of tokens being transferred
    function _update(address from, address to, uint256 amount) internal override {
        // 1. Update Reward State
        _checkpoint(from, to);

        /// Get addresses where funds are allocated to.
        address[] memory targets = allocator().getAllocationTargets(gauge());

        /// Create an allocation struct to pass to the strategy.
        /// We want to withdraw 0, just to get the pending rewards.
        IAllocator.Allocation memory allocation = IAllocator.Allocation({
            asset: asset(),
            gauge: gauge(),
            targets: targets,
            amounts: new uint256[](targets.length)
        });

        /// Checkpoint to get the pending rewards.
        /// @dev Strategy address used as receiver to avoid zero address validation in some tokens
        IStrategy.PendingRewards memory pendingRewards = strategy().withdraw(allocation, POLICY, address(strategy()));

        // 2. Update Balances via Accountant
        ACCOUNTANT.checkpoint(gauge(), from, to, amount.toUint128(), pendingRewards, POLICY);

        // 3. Emit Transfer event
        emit Transfer(from, to, amount);
    }

    /// @notice Mints new vault shares
    /// @dev Updates balances and processes pending rewards
    /// @param to Recipient of new shares
    /// @param amount Amount of shares to mint
    /// @param pendingRewards Rewards to process during mint
    /// @param policy The harvest policy.
    /// @param referrer The address of the referrer. Can be the zero address.
    function _mint(
        address to,
        uint256 amount,
        IStrategy.PendingRewards memory pendingRewards,
        IStrategy.HarvestPolicy policy,
        address referrer
    ) internal {
        ACCOUNTANT.checkpoint({
            gauge: gauge(),
            from: address(0),
            to: to,
            amount: amount.toUint128(),
            pendingRewards: pendingRewards,
            policy: policy,
            referrer: referrer
        });

        emit Transfer(address(0), to, amount);
    }

    /// @notice Burns vault shares
    /// @dev Updates balances and processes pending rewards
    /// @param from Address to burn shares from
    /// @param amount Amount of shares to burn
    /// @param pendingRewards Rewards to process during burn
    /// @param policy The harvest policy.
    function _burn(
        address from,
        uint256 amount,
        IStrategy.PendingRewards memory pendingRewards,
        IStrategy.HarvestPolicy policy
    ) internal {
        ACCOUNTANT.checkpoint({
            gauge: gauge(),
            from: from,
            to: address(0),
            amount: amount.toUint128(),
            pendingRewards: pendingRewards,
            policy: policy
        });

        emit Transfer(from, address(0), amount);
    }

    /// @notice Generates the vault's name
    /// @dev Combines "StakeDAO", underlying asset name, and "Vault"
    /// @return Full vault name
    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("Stake DAO ", IERC20Metadata(asset()).name(), " Vault");
    }

    /// @notice Generates the vault's symbol
    /// @dev Combines "sd-", underlying asset symbol, and "-vault"
    /// @return Full vault symbol
    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("sd-", IERC20Metadata(asset()).symbol(), "-vault");
    }

    /// @notice Gets the vault's decimal places
    /// @dev Matches underlying asset decimals
    /// @return Number of decimal places
    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }
}
