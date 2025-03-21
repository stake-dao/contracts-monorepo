// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC20, IERC20Metadata, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";

/// @title RewardVault
/// @notice An ERC4626-compatible vault that manages deposits, withdrawals, and reward distributions.
/// @dev Implements:
///      1. ERC4626 minimal interface for deposits/withdrawals.
///      2. Integration with Registry (and therefore Strategy, Allocator).
///      3. Delegation of accounting to the Accountant contract.
///      4. Reward distribution logic (claimable rewards).
contract RewardVault is IRewardVault, IERC4626, ERC20 {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    ///////////////////////////////////////////////////////////////
    /// ~ EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when a new reward token is added
    /// @param rewardToken The address of the reward token
    /// @param distributor The address of the rewards distributor
    event RewardTokenAdded(address indexed rewardToken, address indexed distributor);

    /// @notice Emitted when rewards are notified for distribution
    /// @param rewardsToken The address of the reward token
    /// @param amount The amount of rewards to distribute
    /// @param rewardRate The rate at which rewards will be distributed
    event RewardsDeposited(address indexed rewardsToken, uint256 amount, uint128 rewardRate);

    ///////////////////////////////////////////////////////////////
    /// ~ ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice The error thrown when caller is not the owner or approved
    error NotApproved();

    /// @notice The error thrown when the address is zero
    error ZeroAddress();

    /// @notice Error thrown when the caller is not allowed.
    error OnlyAllowed();

    /// @notice Error thrown when the caller is not the registrar.
    error OnlyRegistrar();

    /// @notice Error thrown when the reward token is not valid
    error InvalidRewardToken();

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

    /// @notice Whether to trigger a harvest on deposit and withdraw.
    bool public immutable TRIGGER_HARVEST;

    /// @notice The protocol controller address.
    IAccountant public immutable ACCOUNTANT;

    /// @notice The protocol controller address.
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    /// @notice The maximum number of reward tokens that can be added.
    uint256 public constant MAX_REWARD_TOKEN_COUNT = 10;

    /// @notice The default rewards duration.
    uint32 public constant DEFAULT_REWARDS_DURATION = 7 days;

    ///////////////////////////////////////////////////////////////
    /// ~ STORAGE STRUCTURES
    ///////////////////////////////////////////////////////////////

    /// @notice Reward data structure
    /// @dev This struct fits in 2 storage slots.
    struct RewardData {
        // address of the authorized rewards distributor
        address rewardsDistributor;
        // duration of the rewards distribution
        uint32 rewardsDuration;
        // timestamp at which the rewards was last updated
        uint32 lastUpdateTime;
        // timestamp at which the rewards period will finish
        uint32 periodFinish;
        // number of rewards distributed per second
        uint128 rewardRate;
        // total rewards accumulated per token since the last update, used as a baseline for calculating new rewards
        uint128 rewardPerTokenStored;
    }

    /// @notice Account data structure
    /// @dev This struct fits in 1 storage slot.
    struct AccountData {
        // total rewards paid out to the account since the last update
        uint128 rewardPerTokenPaid;
        // total rewards currently available for the account to claim
        uint128 claimable;
    }

    ///////////////////////////////////////////////////////////////
    /// ~ STATE VARIABLES
    ///////////////////////////////////////////////////////////////

    /// @notice List of active reward tokens
    address[] internal rewardTokens;

    /// @notice Mapping of reward token to its reward data
    mapping(address rewardToken => RewardData rewardData) public rewardData;

    /// @notice Account reward data mapping
    mapping(address accountAddress => mapping(address rewardToken => AccountData accountData)) public accountData;

    ///////////////////////////////////////////////////////////////
    /// ~ MODIFIERS
    ///////////////////////////////////////////////////////////////

    /// @notice Modifier to check if the caller is allowed by the protocol controller to do a specific action
    /// @custom:reverts OnlyAllowed if the caller is not allowed.
    modifier onlyAllowed() {
        require(PROTOCOL_CONTROLLER.allowed(address(this), msg.sender, msg.sig), OnlyAllowed());

        _;
    }

    modifier onlyRegistrar() {
        require(PROTOCOL_CONTROLLER.isRegistrar(msg.sender), OnlyRegistrar());

        _;
    }

    /// @notice Initializes the vault with basic ERC20 metadata
    /// @dev Sets up the vault with a standard name and symbol prefix
    /// @param protocolId The protocol ID.
    /// @param protocolController The protocol controller address
    /// @param accountant The accountant address
    /// @param triggerHarvest Whether to trigger a harvest on deposit and withdraw.
    /// @custom:reverts ZeroAddress if the accountant or protocol controller address is the zero address.
    constructor(bytes4 protocolId, address protocolController, address accountant, bool triggerHarvest)
        ERC20(string.concat("StakeDAO Vault"), string.concat("sd-vault"))
    {
        require(accountant != address(0) && protocolController != address(0), ZeroAddress());

        PROTOCOL_ID = protocolId;
        ACCOUNTANT = IAccountant(accountant);
        PROTOCOL_CONTROLLER = IProtocolController(protocolController);
        TRIGGER_HARVEST = triggerHarvest;
    }

    ///////////////////////////////////////////////////////////////
    /// ~ EXTERNAL/PUBLIC USER-FACING - DEPOSIT & MINT
    ///////////////////////////////////////////////////////////////

    /// @notice Deposits assets into the vault and mints shares to `receiver`.
    /// @dev Handles deposit allocation through strategy and updates rewards.
    /// @param assets The amount of assets to deposit.
    /// @param receiver The address to receive the minted shares. If the receiver is the zero address, the shares will be minted to the caller.
    /// @return _ The amount of assets deposited.
    function deposit(uint256 assets, address receiver) public returns (uint256) {
        if (receiver == address(0)) receiver = msg.sender;

        _deposit(msg.sender, receiver, assets, assets);

        // return the amount of assets deposited. Thanks to the 1:1 relationship between assets and shares
        // the amount of assets deposited is the same as the amount of shares minted
        return assets;
    }

    /// @notice Mints exact `shares` to `receiver` by depositing assets.
    /// @dev Due to the 1:1 relationship between the assets and the shares,
    ///      the mint function is a wrapper of the deposit function.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address to receive the minted shares.
    /// @return _ The amount of shares minted.
    function mint(uint256 shares, address receiver) public returns (uint256) {
        return deposit(shares, receiver);
    }

    /// @dev Internal function to deposit assets into the vault.
    ///      1. Update the reward state for the receiver.
    ///      2. Get the deposit allocation.
    ///      3. Transfer assets to strategy.
    ///      4. Strategy deposits.
    ///      5. Mint shares (accountant checkpoint).
    ///      6. Emit Deposit event.
    /// @param account The address of the account to deposit assets from.
    /// @param receiver The address to receive the minted shares.
    /// @param assets The amount of assets to deposit.
    /// @param shares The amount of shares to mint.
    function _deposit(address account, address receiver, uint256 assets, uint256 shares) internal {
        // Update the reward state for the receiver
        _checkpoint(receiver, address(0));

        // Get the address of the allocator contract from the protocol controller
        // then fetch the recommended deposit allocation from the allocator
        IAllocator.Allocation memory allocation = allocator().getDepositAllocation(asset(), gauge(), assets);

        // Get the address of the asset from the clone's immutable args then for each target recommended by
        // the allocator, transfer the amount from the account to the target
        IERC20 _asset = IERC20(asset());
        for (uint256 i; i < allocation.targets.length; i++) {
            SafeERC20.safeTransferFrom(_asset, account, allocation.targets[i], allocation.amounts[i]);
        }

        // Get the address of the strategy contract from the protocol controller
        // then process the deposit of the allocation
        IStrategy.PendingRewards memory pendingRewards = strategy().deposit(allocation, TRIGGER_HARVEST);

        // Mint the shares to the receiver
        _mint(receiver, shares, pendingRewards, TRIGGER_HARVEST);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    ///////////////////////////////////////////////////////////////
    /// ~ EXTERNAL/PUBLIC USER-FACING - WITHDRAW & REDEEM
    ///////////////////////////////////////////////////////////////

    /// @notice Withdraws `assets` from the vault to `receiver` by burning shares from `owner`.
    /// @dev Checks allowances and calls strategy withdrawal logic.
    /// @param assets The amount of assets to withdraw.
    /// @param receiver The address to receive the assets. If the receiver is the zero address, the assets will be sent to the owner.
    /// @param owner The address to burn shares from.
    /// @return _ The amount of assets withdrawn.
    /// @custom:reverts NotApproved if the caller is not allowed to withdraw at least the amount of assets given.
    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256) {
        if (receiver == address(0)) receiver = owner;

        // if the caller isn't the owner, check if the caller is allowed to withdraw the amount of assets
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (assets > allowed) revert NotApproved();
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
        IStrategy.PendingRewards memory pendingRewards = strategy().withdraw(allocation, TRIGGER_HARVEST, receiver);

        // Burn the shares by calling the endpoint function of the accountant contract
        _burn(owner, shares, pendingRewards, TRIGGER_HARVEST);

        if (PROTOCOL_CONTROLLER.isShutdown(gauge())) {
            // Transfer the assets to the receiver. The 1:1 relationship between assets and shares is maintained.
            SafeERC20.safeTransfer(IERC20(asset()), receiver, shares);
        }

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    ///////////////////////////////////////////////////////////////
    /// ~ EXTERNAL/PUBLIC USER-FACING - REWARDS
    ///////////////////////////////////////////////////////////////

    /// @notice Claims multiple reward tokens in a single transaction for the caller.
    /// @param tokens An array of reward tokens to claim.
    /// @param receiver The address to receive the claimed rewards.
    /// @return amounts An array of amounts claimed for each token.
    function claim(address[] calldata tokens, address receiver) public returns (uint256[] memory amounts) {
        return _claim(msg.sender, tokens, receiver);
    }

    /// @notice Claims multiple reward tokens in a single transaction for the given account.
    /// @param account The account to claim rewards for.
    /// @param tokens An array of reward tokens to claim.
    /// @param receiver The address to receive the claimed rewards.
    /// @return amounts An array of amounts claimed for each token.
    /// @custom:reverts OnlyAllowed if the caller is not allowed to claim rewards.
    function claim(address account, address[] calldata tokens, address receiver)
        public
        onlyAllowed
        returns (uint256[] memory amounts)
    {
        return _claim(account, tokens, receiver);
    }

    /// @dev Internal function to claim multiple reward tokens.
    ///      1. Update rewards for the account.
    ///      2. Reset the claimable amount and transfer out the rewards.
    ///      3. Return claimed amounts.
    /// @param accountAddress The address of the account to claim rewards for.
    /// @param tokens An array of reward tokens to claim.
    /// @param receiver The address to receive the claimed rewards.
    /// @return amounts An array of amounts claimed for each token. The length of the array is the same as the length of the tokens array.
    /// @custom:reverts InvalidRewardToken if a token is not a valid reward token.
    function _claim(address accountAddress, address[] calldata tokens, address receiver)
        internal
        returns (uint256[] memory amounts)
    {
        if (receiver == address(0)) receiver = accountAddress;

        // Make sure reward accounting is up to date.
        _checkpoint(accountAddress, address(0));

        amounts = new uint256[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            address rewardToken = tokens[i];
            if (!isRewardToken(rewardToken)) revert InvalidRewardToken();

            // calculate the earned amount for the account on the reward token
            AccountData storage account = accountData[accountAddress][rewardToken];
            uint256 accountEarned = _earned(accountAddress, rewardToken, account.claimable, account.rewardPerTokenPaid);
            if (accountEarned == 0) continue;

            // if the account has earned rewards, set claimable to zero & calculate the new rewardPerTokenPaid
            account.rewardPerTokenPaid = rewardPerToken(rewardToken);
            account.claimable = 0;

            // then transfer the rewards to the receiver and increment the amount claimed
            SafeERC20.safeTransfer(IERC20(rewardToken), receiver, accountEarned);
            amounts[i] = accountEarned;
        }
        return amounts;
    }

    /// @notice Adds a new reward token to the vault.
    /// @param rewardsToken The address of the reward token to add.
    /// @param distributor The address authorized to distribute rewards.
    /// @custom:reverts OnlyAllowed if the caller is not allowed to add a reward token.
    /// @custom:reverts ZeroAddress if the distributor is the zero address.
    /// @custom:reverts RewardAlreadyExists if the reward token already exists.
    /// @custom:reverts MaxRewardTokensExceeded if the maximum number of reward tokens is exceeded.
    function addRewardToken(address rewardsToken, address distributor) external onlyRegistrar {
        // ensure that the distributor is not the zero address
        require(distributor != address(0), ZeroAddress());

        // ensure that the maximum number of reward tokens is not exceeded
        require(rewardTokens.length < MAX_REWARD_TOKEN_COUNT, MaxRewardTokensExceeded());

        // get the reward data for the reward token
        RewardData storage reward = rewardData[rewardsToken];

        // ensure that the reward token does not already exist
        require(_isRewardToken(reward) == false, RewardAlreadyExists());

        // add the reward token to the list of reward tokens
        rewardTokens.push(rewardsToken);

        // Set the reward distributor and duration.
        reward.rewardsDistributor = distributor;
        reward.rewardsDuration = DEFAULT_REWARDS_DURATION;

        emit RewardTokenAdded(rewardsToken, distributor);
    }

    /// @notice Deposits rewards into the vault.
    /// @dev Handles reward rate updates and token transfers.
    /// @param _rewardsToken The reward token being distributed.
    /// @param _amount The amount of rewards to distribute.
    /// @custom:reverts UnauthorizedRewardsDistributor if the caller is not the authorized distributor.
    function depositRewards(address _rewardsToken, uint128 _amount) external {
        // Update reward state for all tokens first.
        _checkpoint(address(0), address(0));

        // get the current reward data
        RewardData storage reward = rewardData[_rewardsToken];

        // check if the caller is the authorized distributor
        if (reward.rewardsDistributor != msg.sender) revert UnauthorizedRewardsDistributor();

        // calculate temporal variables
        uint32 currentTime = uint32(block.timestamp);
        uint32 periodFinish = reward.periodFinish;
        uint32 rewardsDuration = reward.rewardsDuration;
        uint128 newRewardRate;

        // calculate the new reward rate based on the current time and the period finish
        if (currentTime >= periodFinish) {
            newRewardRate = _amount / rewardsDuration;
        } else {
            uint32 remainingTime = periodFinish - currentTime;
            uint128 remainingRewards = remainingTime * reward.rewardRate;
            newRewardRate = (_amount + remainingRewards) / rewardsDuration;
        }

        // Update the reward data
        reward.lastUpdateTime = currentTime;
        reward.periodFinish = currentTime + rewardsDuration;
        reward.rewardRate = newRewardRate;

        // transfer the rewards to the vault
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), _amount);

        emit RewardsDeposited(_rewardsToken, _amount, newRewardRate);
    }

    ///////////////////////////////////////////////////////////////
    /// ~ INTERNAL REWARD UPDATES & HELPERS ~
    ///////////////////////////////////////////////////////////////

    /// @dev Internal function to update reward state for two accounts (optional).
    /// @param _from The account to update. (Can be address(0) if not needed)
    /// @param _to The account to update. (Can be address(0) if not needed)
    function _checkpoint(address _from, address _to) internal {
        uint256 len = rewardTokens.length;

        for (uint256 i; i < len; i++) {
            address token = rewardTokens[i];
            uint128 newRewardPerToken = _updateRewardToken(token);

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
    /// @param token The address of the reward token to update.
    /// @return newRewardPerToken The new calculated reward per token.
    function _updateRewardToken(address token) internal returns (uint128 newRewardPerToken) {
        RewardData storage reward = rewardData[token];

        // get the current reward per token
        newRewardPerToken = _rewardPerToken(reward);

        // Update the last update time and reward per token stored
        reward.lastUpdateTime = _lastTimeRewardApplicable(reward.periodFinish);
        reward.rewardPerTokenStored = newRewardPerToken;
    }

    /// @notice Updates account data with new claimable rewards.
    /// @param accountAddress The address of the account to update.
    /// @param token The address of the reward token to update.
    /// @param newRewardPerToken The new reward per token.
    function _updateAccountData(address accountAddress, address token, uint128 newRewardPerToken) internal {
        AccountData storage account = accountData[accountAddress][token];

        account.claimable = _earned(accountAddress, token, account.claimable, account.rewardPerTokenPaid);
        account.rewardPerTokenPaid = newRewardPerToken;
    }

    /// @notice Returns true if the reward token is valid.
    /// @dev The check is based on the assumption that the distributor is always set for a
    ///      active address and it can not be zero.
    /// @param reward The address of the reward token to check.
    /// @return _ True if the reward token is valid, false otherwise.
    function _isRewardToken(RewardData storage reward) internal view returns (bool) {
        return reward.rewardsDistributor != address(0);
    }

    ///////////////////////////////////////////////////////////////
    /// ~ VIEW / PURE METHODS ~
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
        bytes memory args = Clones.fetchCloneArgs(address(this));
        address token;
        assembly {
            token := mload(add(args, 40))
        }
        return token;
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
        return type(uint256).max;
    }

    /// @notice Returns the maximum amount of shares that can be minted.
    /// @dev Due to the 1:1 relationship between assets and shares, the max mint
    ///      is the same as the max deposit.
    /// @param __ This parameter is not used and is included to satisfy the interface. Pass whatever you want to.
    /// @return _ The maximum amount of shares that can be minted.
    function maxMint(address __) external pure returns (uint256) {
        return maxDeposit(__);
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

    /// @notice Returns the duration of the rewards distribution for a given reward token.
    /// @param token The address of the reward token to calculate the rewards duration for.
    /// @return _ The rewards duration for the given reward token.
    function getRewardsDuration(address token) external view returns (uint32) {
        return rewardData[token].rewardsDuration;
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

    /// @notice Returns the last time reward is applicable for a given reward token.
    /// @param token The address of the reward token to calculate the last time reward is applicable for.
    /// @return _ The last time reward is applicable for the given reward token.
    function lastTimeRewardApplicable(address token) external view returns (uint256) {
        return _lastTimeRewardApplicable(rewardData[token].periodFinish);
    }

    /// @notice Returns the last time reward applicable for a given period finish.
    /// @dev This code is expected to live until February 7, 2106, at 06:28:15 UTC
    /// @param periodFinish The period finish time for the given reward token.
    /// @return _ The last time reward applicable for the given period finish.
    function _lastTimeRewardApplicable(uint32 periodFinish) internal view returns (uint32) {
        return Math.min(block.timestamp, periodFinish).toUint32();
    }

    /// @notice Returns the new calculated reward per token for a given reward token.
    /// @param reward A storage pointer to the reward data for the given reward token.
    /// @return _ The new calculated reward per token for the given reward token.
    function _rewardPerToken(RewardData storage reward) internal view returns (uint128) {
        uint128 _totalSupply = _safeTotalSupply();

        if (_totalSupply == 0) return reward.rewardPerTokenStored;

        uint256 timeDelta = _lastTimeRewardApplicable(reward.periodFinish) - reward.lastUpdateTime;
        uint256 rewardRatePerToken = 0;

        if (timeDelta > 0 && _totalSupply > 0) {
            // Calculate reward per token for the time period
            rewardRatePerToken = (timeDelta * reward.rewardRate * 1e18) / _totalSupply;
        }

        return (reward.rewardPerTokenStored + rewardRatePerToken).toUint128();
    }

    /// @notice Returns the reward per token for a given reward token.
    /// @param token The address of the reward token to calculate the reward per token for.
    /// @return _ The reward per token for the given reward token.
    function rewardPerToken(address token) public view returns (uint128) {
        return _rewardPerToken(rewardData[token]);
    }

    /// @notice Returns the earned reward for a given account, including the claimable amount.
    /// @param accountAddress The address of the account to calculate the earned reward for.
    /// @param token The address of the reward token to calculate the earned reward for.
    /// @return _ The earned reward for the given account and reward token.
    function earned(address accountAddress, address token) external view returns (uint128) {
        AccountData storage account = accountData[accountAddress][token];

        return _earned(accountAddress, token, account.claimable, account.rewardPerTokenPaid);
    }

    /// @notice Returns the earned reward for a given account, including the claimable amount.
    /// @param accountAddress The address of the account to calculate the earned reward for.
    /// @param token The address of the reward token to calculate the earned reward for.
    /// @param userClaimable The claimable amount for the given account and reward token.
    /// @param userRewardPerTokenPaid The reward per token paid for the given account and reward token.
    /// @return _ The earned reward for the given account and reward token.
    function _earned(address accountAddress, address token, uint128 userClaimable, uint128 userRewardPerTokenPaid)
        internal
        view
        returns (uint128)
    {
        uint128 newEarned =
            balanceOf(accountAddress).mulDiv(rewardPerToken(token) - userRewardPerTokenPaid, 1e18).toUint128();

        return userClaimable + newEarned;
    }

    /// @notice Returns the reward for a given reward token for the duration of the rewards distribution.
    /// @param token The address of the reward token to calculate the reward for.
    /// @return _ The calculated new reward for duration
    function getRewardForDuration(address token) external view returns (uint256) {
        RewardData storage reward = rewardData[token];

        return reward.rewardRate * reward.rewardsDuration;
    }

    /// @notice Updates the reward state for an account
    /// @param account The account to update rewards for.
    function checkpoint(address account) external {
        _checkpoint(account, address(0));
    }

    ///////////////////////////////////////////////////////////////
    /// ~ PROTOCOL_CONTROLLER / CLONE ARGUMENT GETTERS ~
    ///////////////////////////////////////////////////////////////

    /// @notice Returns the gauge contract passed as an immutable argument to the clone.
    /// @return _gauge The address of the gauge contract.
    /// @custom:reverts CloneArgsNotFound if the clone has been incorrectly initialized.
    function gauge() public view returns (address _gauge) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _gauge := mload(add(args, 20))
        }
    }

    /// @notice Returns the allocator contract by fetching it from the protocol controller.
    /// @return _allocator The allocator contract.
    function allocator() public view returns (IAllocator _allocator) {
        return IAllocator(PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID));
    }

    /// @notice Returns the strategy contract by fetching it from the protocol controller.
    /// @return _strategy The strategy contract.
    function strategy() public view returns (IStrategy _strategy) {
        return IStrategy(PROTOCOL_CONTROLLER.strategy(PROTOCOL_ID));
    }

    ///////////////////////////////////////////////////////////////
    /// ~ ERC20 OVERRIDES ~
    ///////////////////////////////////////////////////////////////

    /// @notice Used by ERC20 transfers to update the reward state and the balances by calling the checkpoint function of the accountant contract.
    /// @dev Delegates balance updates to the Accountant, then updates rewards.
    /// @param from The address of the account to transfer shares from.
    /// @param to The address of the account to transfer shares to.
    /// @param amount The amount of shares to transfer.
    function _update(address from, address to, uint256 amount) internal override {
        // 1. Update Balances via Accountant.
        ACCOUNTANT.checkpoint(
            gauge(), from, to, uint128(amount), IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}), false
        );

        // 2. Update Reward State.
        _checkpoint(from, to);

        // 3. Emit Transfer event.
        emit Transfer(from, to, amount);
    }

    /// @dev Mints shares by calling the checkpoint function of the accountant contract.
    /// @param to The address of the account to mint shares to.
    /// @param amount The amount of shares to mint.
    /// @param pendingRewards The pending rewards for the given account and reward token.
    /// @param harvested Whether the minting operation should also harvest the rewards.
    function _mint(address to, uint256 amount, IStrategy.PendingRewards memory pendingRewards, bool harvested)
        internal
    {
        ACCOUNTANT.checkpoint(gauge(), address(0), to, uint128(amount), pendingRewards, harvested);
    }

    /// @dev Burns shares by calling the checkpoint function of the accountant contract.
    /// @param from The address of the account to burn shares from.
    /// @param amount The amount of shares to burn.
    /// @param pendingRewards The pending rewards for the given account and reward token.
    /// @param harvested Whether the burning operation should also harvest the rewards.
    function _burn(address from, uint256 amount, IStrategy.PendingRewards memory pendingRewards, bool harvested)
        internal
    {
        ACCOUNTANT.checkpoint(gauge(), from, address(0), uint128(amount), pendingRewards, harvested);
    }

    /// @notice Returns the name of the vault. The name is the same as the asset name with the prefix "StakeDAO " and the suffix " Vault".
    /// @return _ The name of the vault.
    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("StakeDAO ", IERC20Metadata(asset()).name(), " Vault");
    }

    /// @notice Returns the symbol of the vault. The symbol is the same as the asset symbol with the prefix "sd-" and the suffix "-vault".
    /// @return _ The symbol of the vault.
    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("sd-", IERC20Metadata(asset()).symbol(), "-vault");
    }

    /// @notice Returns the number of decimals of the vault.
    /// @return _ The number of decimals of the vault.
    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return IERC20Metadata(asset()).decimals();
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
}
