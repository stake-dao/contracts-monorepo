// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, IERC20Metadata, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IAllocator} from "src/interfaces/IAllocator.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
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
    using SafeCast for uint256;

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

    /// @notice The error thrown when the address is zero
    error ZeroAddress();

    /// @notice Error thrown when the caller is not allowed.
    error OnlyAllowed();

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

    /// @notice The protocol controller address.
    IAccountant public immutable ACCOUNTANT;

    /// @notice The protocol controller address.
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    /// @notice The maximum number of reward tokens that can be added.
    uint256 constant MAX_REWARD_TOKEN_COUNT = 10;

    ///////////////////////////////////////////////////////////////
    /// ~ STORAGE STRUCTURES
    ///////////////////////////////////////////////////////////////

    /// @notice Reward data structure
    struct RewardData {
        address rewardsDistributor;
        uint32 rewardsDuration;
        uint32 lastUpdateTime;
        uint32 periodFinish;
        uint128 rewardRate;
        uint128 rewardPerTokenStored;
    }

    /// @notice Account data structure
    struct AccountData {
        uint128 rewardPerTokenPaid;
        uint128 claimable;
    }

    ///////////////////////////////////////////////////////////////
    /// ~ STATE VARIABLES
    ///////////////////////////////////////////////////////////////

    /// @notice List of active reward tokens
    address[] public rewardTokens;

    /// @notice Mapping of reward token to its existence
    mapping(address => bool) public isRewardToken;

    /// @notice Mapping of reward token to its packed reward data
    mapping(address => RewardData) private rewardData;

    /// @notice Account reward data mapping
    mapping(address => mapping(address => AccountData)) private accountData;

    /// @notice Initializes the vault with basic ERC20 metadata
    /// @dev Sets up the vault with a standard name and symbol prefix
    constructor(bytes4 protocolId, address protocolController, address accountant)
        ERC20(string.concat("StakeDAO Vault"), string.concat("sd-vault"))
    {
        require(accountant != address(0) && protocolController != address(0), ZeroAddress());

        PROTOCOL_ID = protocolId;
        ACCOUNTANT = IAccountant(accountant);
        PROTOCOL_CONTROLLER = IProtocolController(protocolController);
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

        IStrategy.PendingRewards memory pendingRewards = strategy().deposit(allocation);

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

        IAllocator.Allocation memory allocation = allocator().getWithdrawalAllocation(gauge(), assets);

        IStrategy.PendingRewards memory pendingRewards = strategy().withdraw(allocation);

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
        require(PROTOCOL_CONTROLLER.allowed(address(this), msg.sender, msg.sig), "OnlyAllowed");
        return _claim(account, tokens, receiver);
    }

    /// @dev Internal function to claim multiple reward tokens.
    ///      1. Update rewards for the account.
    ///      2. Reset the claimable amount and transfer out the rewards.
    ///      3. Return claimed amounts.
    function _claim(address accountAddress, address[] calldata tokens_, address receiver)
        internal
        returns (uint256[] memory amounts)
    {
        if (receiver == address(0)) receiver = accountAddress;

        // Make sure reward accounting is up to date.
        _updateReward(accountAddress, address(0));

        amounts = new uint256[](tokens_.length);

        for (uint256 i = 0; i < tokens_.length; i++) {
            address rewardToken = tokens_[i];
            if (!isRewardToken[rewardToken]) revert InvalidRewardToken();

            AccountData storage account = accountData[accountAddress][rewardToken];
            uint256 accountEarned = _earned(accountAddress, rewardToken, account.claimable, account.rewardPerTokenPaid);
            if (accountEarned == 0) continue;

            // Reset claimable to zero & set rewardPerTokenPaid to current
            account.rewardPerTokenPaid = rewardPerToken(rewardToken);
            account.claimable = 0;

            SafeERC20.safeTransfer(IERC20(rewardToken), receiver, accountEarned);
            amounts[i] = accountEarned;
        }
        return amounts;
    }

    /// @notice Adds a new reward token to the vault.
    /// @param _rewardsToken The address of the reward token to add.
    /// @param _distributor The address authorized to distribute rewards.
    function addRewardToken(address _rewardsToken, address _distributor) external {
        // check if the caller is allowed to add a reward token
        require(PROTOCOL_CONTROLLER.allowed(address(this), msg.sender, msg.sig), "OnlyAllowed");

        // check if the reward token already exists
        if (isRewardToken[_rewardsToken]) revert RewardAlreadyExists();

        // check if the maximum number of reward tokens is exceeded
        if (rewardTokens.length >= MAX_REWARD_TOKEN_COUNT) revert MaxRewardTokensExceeded();

        // add the reward token to the list of reward tokens
        rewardTokens.push(_rewardsToken);
        isRewardToken[_rewardsToken] = true;

        // Set the reward distributor and duration.
        RewardData storage reward = rewardData[_rewardsToken];
        reward.rewardsDistributor = _distributor;
        reward.rewardsDuration = 7 days;

        emit RewardTokenAdded(_rewardsToken, _distributor);
    }

    /// @notice Deposits rewards into the vault.
    /// @dev Handles reward rate updates and token transfers.
    /// @param _rewardsToken The reward token being distributed.
    /// @param _amount The amount of rewards to distribute.
    function depositRewards(address _rewardsToken, uint128 _amount) external {
        // Update reward state for all tokens first.
        _updateReward(address(0), address(0));

        // check if the caller is the authorized distributor
        if (getRewardsDistributor(_rewardsToken) != msg.sender) revert UnauthorizedRewardsDistributor();

        // transfer the rewards to the vault
        // TODO: external calls at the end of the function
        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), _amount);

        // calculate temporal variables
        uint32 currentTime = uint32(block.timestamp);
        uint32 periodFinish = getPeriodFinish(_rewardsToken);
        uint32 rewardsDuration = getRewardsDuration(_rewardsToken);
        uint128 newRewardRate;

        // get the current reward data
        RewardData storage reward = rewardData[_rewardsToken];

        // calculate the new reward rate based on the current time and the period finish
        if (currentTime >= periodFinish) {
            newRewardRate = _amount / rewardsDuration;
        } else {
            uint32 remainingTime = periodFinish - currentTime;
            uint128 remainingRewards = remainingTime * reward.rewardRate;
            newRewardRate = (_amount + remainingRewards) / rewardsDuration;
        }

        // Update every reward data except the distributor
        reward.rewardsDuration = rewardsDuration;
        reward.lastUpdateTime = currentTime;
        reward.periodFinish = currentTime + rewardsDuration;
        reward.rewardRate = newRewardRate;
        reward.rewardPerTokenStored = getRewardPerTokenStored(_rewardsToken);

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
            uint128 newRewardPerToken = _updateRewardToken(token, currentTime);

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
    function _updateRewardToken(address token, uint32 currentTime) internal returns (uint128 newRewardPerToken) {
        RewardData storage reward = rewardData[token];

        // get the current reward per token
        newRewardPerToken = rewardPerToken(token);

        // Update the last update time and reward per token stored
        reward.lastUpdateTime = currentTime;
        reward.rewardPerTokenStored = newRewardPerToken;
    }

    /// @dev Updates account data with new claimable rewards.
    function _updateAccountData(address accountAddress, address token, uint128 newRewardPerToken) internal {
        AccountData storage account = accountData[accountAddress][token];

        account.claimable = _earned(accountAddress, token, account.claimable, account.rewardPerTokenPaid);
        account.rewardPerTokenPaid = newRewardPerToken;
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
        return rewardData[token].rewardsDistributor;
    }

    /// @notice Returns the duration of the rewards distribution for a given reward token.
    function getRewardsDuration(address token) public view returns (uint32) {
        return rewardData[token].rewardsDuration;
    }

    /// @notice Returns the last update time for a given reward token.
    function getLastUpdateTime(address token) public view returns (uint32) {
        return rewardData[token].lastUpdateTime;
    }

    /// @notice Returns the period finish time for a given reward token.
    function getPeriodFinish(address token) public view returns (uint32) {
        return rewardData[token].periodFinish;
    }

    /// @notice Returns the reward rate for a given reward token.
    function getRewardRate(address token) public view returns (uint128) {
        return rewardData[token].rewardRate;
    }

    /// @notice Returns the reward per token stored for a given reward token.
    function getRewardPerTokenStored(address token) public view returns (uint128) {
        return rewardData[token].rewardPerTokenStored;
    }

    /// @notice Returns the last time reward applicable for a given reward token.
    function lastTimeRewardApplicable(address token) public view returns (uint256) {
        return _lastTimeRewardApplicable(getPeriodFinish(token));
    }

    /// @notice Returns the last time reward applicable for a given period finish.
    /// @dev This code is expected to live until February 7, 2106, at 06:28:15 UTC
    function _lastTimeRewardApplicable(uint32 periodFinish) internal view returns (uint32) {
        return Math.min(block.timestamp, periodFinish).toUint32();
    }

    /// @notice Returns the reward per token for a given reward token.
    function rewardPerToken(address token) public view returns (uint128) {
        uint128 _totalSupply = _safeTotalSupply();

        if (_totalSupply == 0) return getRewardPerTokenStored(token);

        // get the current reward data
        RewardData storage reward = rewardData[token];

        // calculate the reward per token based on the last update time, the ending period, the reward rate and the total supply
        return reward.rewardPerTokenStored
            + (
                (_lastTimeRewardApplicable(reward.periodFinish) - reward.lastUpdateTime) * reward.rewardRate * 1e18
                    / _totalSupply
            );
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

    /// @notice Returns the gauge.
    function gauge() public view returns (address _gauge) {
        bytes memory args = Clones.fetchCloneArgs(address(this));
        assembly {
            _gauge := mload(add(args, 60))
        }
    }

    /// @notice Returns the allocator.
    function allocator() public view returns (IAllocator _allocator) {
        return IAllocator(PROTOCOL_CONTROLLER.allocator(PROTOCOL_ID));
    }

    /// @notice Returns the strategy.
    function strategy() public view returns (IStrategy _strategy) {
        return IStrategy(PROTOCOL_CONTROLLER.strategy(PROTOCOL_ID));
    }

    ///////////////////////////////////////////////////////////////
    /// ~ ERC20 OVERRIDES ~
    ///////////////////////////////////////////////////////////////

    /// @notice Used by ERC20 transfers to update balances and reward state.
    /// @dev Delegates balance updates to the Accountant, then updates rewards.
    function _update(address from, address to, uint256 amount) internal override {
        // 1. Update Balances via Accountant.
        // TODO: remove the unsafe cast to uint128 once the implementation is cleaned up.
        ACCOUNTANT.checkpoint(
            gauge(), from, to, uint128(amount), IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}), false
        );

        // 2. Update Reward State.
        _updateReward(from, to);

        // 3. Emit Transfer event.
        emit Transfer(from, to, amount);
    }

    /// @dev Mints shares (accountant checkpoint).
    function _mint(address to, uint256 amount, IStrategy.PendingRewards memory pendingRewards, bool harvested)
        internal
    {
        // TODO: remove the unsafe cast to uint128 once the implementation is cleaned up.
        ACCOUNTANT.checkpoint(gauge(), address(0), to, uint128(amount), pendingRewards, harvested);
    }

    /// @dev Burns shares (accountant checkpoint).
    function _burn(address from, uint256 amount, IStrategy.PendingRewards memory pendingRewards, bool harvested)
        internal
    {
        // TODO: remove the unsafe cast to uint128 once the implementation is cleaned up.
        ACCOUNTANT.checkpoint(gauge(), from, address(0), uint128(amount), pendingRewards, harvested);
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
        return ACCOUNTANT.totalSupply(address(this));
    }

    function _safeTotalSupply() internal view returns (uint128) {
        return totalSupply().toUint128();
    }

    /// @notice Returns the balance of the vault for a given account.
    function balanceOf(address account) public view override(ERC20, IERC20) returns (uint256) {
        return ACCOUNTANT.balanceOf(address(this), account);
    }
}
