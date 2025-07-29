// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IStrategyWrapper} from "src/interfaces/IStrategyWrapper.sol";

/// @title Stake DAO Strategy Wrapper
/// @notice Non-transferable ERC20 wrapper for Stake DAO RewardVault shares. It is designed for use as collateral in lending markets.
/// @dev   - Allows users to deposit RewardVault shares or underlying LP tokens, and receive non-transferable tokens (1:1 ratio)
///        - While the ERC20 tokens are held (even as collateral in lending markets), users can claim both main protocol rewards and extra rewards
///        - Handles the edge case where the main reward token is also listed as an extra reward
///        - Integrates with Stake DAO's reward and checkpointing logic to ensure users always receive the correct rewards, regardless of the custody
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
/// @custom:github https://github.com/stake-dao/contracts-monorepo
contract StrategyWrapper is ERC20, IStrategyWrapper, Ownable2Step, ReentrancyGuardTransient {
    ///////////////////////////////////////////////////////////////
    // --- IMMUTABLES
    ///////////////////////////////////////////////////////////////

    /// @notice Reward token emitted by the Accountant (e.g. CRV)
    IERC20 public immutable MAIN_REWARD_TOKEN;

    /// @notice The slot of the main reward token in the user checkpoint
    /// @dev    In order to optimize the storage, the main reward token is tracked in the same
    ///         mapping as the extra reward tokens by using the `address(0)` slot.
    ///         This internal value that is never supposed to be exposed must be used to read/write
    ///         the main reward token state.
    /// @dev    `address(0)` has been chosen to avoid collisions with the extra reward tokens.
    address private constant MAIN_REWARD_TOKEN_SLOT = address(0);

    /// @notice The address of the token that is being wrapped
    IRewardVault public immutable REWARD_VAULT;

    /// @notice Gauge backing the wrapped RewardVault
    address public immutable GAUGE;

    /// @notice The address of the accountant contract
    IAccountant public immutable ACCOUNTANT;

    /// @dev Precision used by Accountant.integral (usually 1e27)
    uint128 public immutable ACCOUNTANT_SCALING_FACTOR;

    /// @notice Tracks user deposit data and reward checkpoints
    /// @param balance User's wrapped-share balance
    /// @param rewardPerTokenPaid Last per-token accumulator seen
    struct UserCheckpoint {
        uint256 balance;
        mapping(address token => uint256 amount) rewardPerTokenPaid;
    }

    /// @notice User checkpoint data including his deposit balance and the amount of rewards he has claimed for each token
    ///         Both the main reward token and the extra reward tokens are tracked in the same mapping.
    /// @dev    The main reward token is tracked in `rewardPerTokenPaid[address(0)]`
    mapping(address user => UserCheckpoint checkpoint) public userCheckpoints;

    /// @notice Accumulated rewards per token. Track the extra reward tokens only.
    /// @dev    The main reward token is tracked by fetching the latest value from the Accountant.
    mapping(address token => uint256 amount) public extraRewardPerToken;

    ///////////////////////////////////////////////////////////////
    // --- EVENTS/ERRORS
    ///////////////////////////////////////////////////////////////

    /// @dev Emitted when a user claims rewards for themselves or for another user
    /// @param token     Address of the reward token transferred
    /// @param caller    Address that initiated the claim (the caller)
    /// @param receiver  Address that received the rewards (the receiver)
    /// @param amount    Amount transferred (same decimals as `token`)
    event Claimed(address indexed token, address indexed caller, address indexed receiver, uint256 amount);

    /// @dev Emitted when a user deposits shares for themselves
    event Deposited(address indexed user, uint256 amount);

    /// @dev Emitted when a user withdraws shares for themselves or for another user
    event Withdrawn(address indexed user, address indexed receiver, uint256 amount);

    /// @dev Thrown when a given amount is zero
    error ZeroAmount();

    /// @dev Thrown when a given address is the zero address
    error ZeroAddress();

    /// @dev Thrown when the provided token list is empty
    error InvalidTokens();

    /// @param rewardVault The reward vault contract
    /// @param _owner The owner of the contract
    /// @custom:reverts ZeroAddress if the reward vault or _owner address are the zero address
    constructor(IRewardVault rewardVault, address _owner) ERC20("", "") Ownable(_owner) {
        require(address(rewardVault) != address(0) && _owner != address(0), ZeroAddress());

        IAccountant accountant = rewardVault.ACCOUNTANT();

        // Store the immutable variables
        GAUGE = rewardVault.gauge();
        ACCOUNTANT = accountant;
        REWARD_VAULT = rewardVault;
        MAIN_REWARD_TOKEN = IERC20(accountant.REWARD_TOKEN());
        ACCOUNTANT_SCALING_FACTOR = accountant.SCALING_FACTOR();

        // Approve the asset token to the reward vault
        SafeERC20.forceApprove(IERC20(rewardVault.asset()), address(rewardVault), type(uint256).max);
    }

    ///////////////////////////////////////////////////////////////
    // --- DEPOSIT
    ///////////////////////////////////////////////////////////////

    /// @notice Wrap **all** RewardVault shares owned by the caller into wrapper tokens (1:1 ratio)
    /// @dev Use this when you ALREADY hold RewardVault shares.
    ///      If you already have wrapped tokens, any pending main and extra rewards will be
    ///      automatically claimed before the new deposit to prevent reward loss.
    /// @custom:reverts ZeroAmount If the caller's share balance is zero
    function depositShares() external {
        depositShares(REWARD_VAULT.balanceOf(msg.sender));
    }

    /// @notice Wrap `amount` RewardVault shares into wrapper tokens (1:1 ratio)
    /// @param amount Number of RewardVault shares the caller wants to wrap
    /// @dev Use this when you ALREADY hold RewardVault shares and wish to wrap a specific portion of them.
    ///      If you already have wrapped tokens, any pending main and extra rewards will be
    ///      automatically claimed before the new deposit to prevent reward loss.
    /// @custom:reverts ZeroAmount If `amount` is zero
    function depositShares(uint256 amount) public nonReentrant {
        require(amount > 0, ZeroAmount());

        // 1. Transfer caller's shares to this contract (checkpoint)
        SafeERC20.safeTransferFrom(IERC20(address(REWARD_VAULT)), msg.sender, address(this), amount);

        _deposit(amount);
    }

    /// @notice Convert **all** underlying LP tokens owned by the caller into RewardVault
    ///         shares and immediately wrap those shares into wrapper tokens (LP → share → wrapper)
    /// @dev Use this when you DO NOT own RewardVault shares yet, only the raw LP tokens.
    ///      If you already have wrapped tokens, any pending main and extra rewards will be
    ///      automatically claimed before the new deposit to prevent reward loss.
    /// @custom:reverts ZeroAmount If the caller's LP balance is zero
    function depositAssets() external {
        depositAssets(IERC20(REWARD_VAULT.asset()).balanceOf(msg.sender));
    }

    /// @notice Convert `amount` underlying LP tokens into RewardVault shares and
    ///         immediately wrap those shares into wrapper tokens (LP → share → wrapper)
    /// @param amount Amount of underlying LP tokens provided by the caller
    /// @dev Use this when you DO NOT own RewardVault shares yet, only the raw LP tokens,
    ///      and wish to wrap a specific portion of them.
    ///      If you already have wrapped tokens, any pending main and extra rewards will be
    ///      automatically claimed before the new deposit to prevent reward loss.
    /// @custom:reverts ZeroAmount If `amount` is zero
    function depositAssets(uint256 amount) public nonReentrant {
        require(amount > 0, ZeroAmount());

        // 1. Get RewardVault's shares by depositing the underlying protocol LP tokens (checkpoint)
        SafeERC20.safeTransferFrom(IERC20(REWARD_VAULT.asset()), msg.sender, address(this), amount);
        uint256 shares = REWARD_VAULT.deposit(amount, address(this), address(this));

        _deposit(shares);
    }

    function _deposit(uint256 amount) internal {
        // 1. Update the internal user checkpoint
        UserCheckpoint storage checkpoint = userCheckpoints[msg.sender];
        if (checkpoint.balance != 0) _claimAllRewards(msg.sender);
        checkpoint.balance += amount;

        // 2. Keep track of the Main reward token checkpoint
        checkpoint.rewardPerTokenPaid[MAIN_REWARD_TOKEN_SLOT] = _getGlobalIntegral();

        // 3. Keep track of the Extra reward tokens checkpoints at deposit time
        address[] memory rewardTokens = REWARD_VAULT.getRewardTokens();
        for (uint256 i; i < rewardTokens.length; i++) {
            checkpoint.rewardPerTokenPaid[rewardTokens[i]] = extraRewardPerToken[rewardTokens[i]];
        }

        // 4. Mint wrapped tokens (1:1) for the caller
        _mint(msg.sender, amount);

        emit Deposited(msg.sender, amount);
    }

    ///////////////////////////////////////////////////////////////
    // --- WITHDRAW
    ///////////////////////////////////////////////////////////////

    /// @notice Withdraws all the assets and claims pending rewards for the caller
    function withdraw() external {
        withdraw(balanceOf(msg.sender), msg.sender);
    }

    /// @notice Withdraws the given amount of assets and claims main/extra pending rewards for the receiver
    /// @param amount Amount of wrapped tokens to burn
    /// @param receiver The address to receive the underlying reward vault shares
    /// @custom:reverts ZeroAmount if the given amount is zero
    /// @custom:reverts ZeroAddress if the receiver address is the zero address
    function withdraw(uint256 amount, address receiver) public nonReentrant {
        require(amount > 0, ZeroAmount());
        require(receiver != address(0), ZeroAddress());

        // 1. Claim all the pending rewards (main + extra) for the receiver
        _claimAllRewards(receiver);

        // 2. Update the internal user checkpoint
        UserCheckpoint storage checkpoint = userCheckpoints[msg.sender];
        checkpoint.balance -= amount;

        // 4. Burn caller's wrapped tokens
        _burn(msg.sender, amount);

        // 5. Transfer the underlying RewardVault shares back to the receiver
        SafeERC20.safeTransfer(IERC20(address(REWARD_VAULT)), receiver, amount);

        emit Withdrawn(msg.sender, receiver, amount);
    }

    ///////////////////////////////////////////////////////////////
    // --- REWARDS
    ///////////////////////////////////////////////////////////////

    /// @notice Claims the caller's main reward token for himself
    /// @return amount Amount of main reward tokens claimed
    function claim() external nonReentrant returns (uint256 amount) {
        return _claim(msg.sender);
    }

    /// @notice Claims the caller's main reward token for the receiver
    /// @param receiver The address to receive the main reward tokens
    /// @return amount Amount of main reward tokens claimed
    /// @custom:reverts ZeroAddress if the receiver address is the zero address
    function claim(address receiver) external nonReentrant returns (uint256 amount) {
        return _claim(receiver);
    }

    function _claim(address receiver) internal returns (uint256 amount) {
        require(receiver != address(0), ZeroAddress());

        // 1. Pull the latest data from the Accountant and the total supply of the wrapper
        IAccountant.AccountData memory wrapper = ACCOUNTANT.accounts(address(REWARD_VAULT), address(this));
        uint256 globalIntegral = _getGlobalIntegral();
        uint256 supply = totalSupply();

        // 2. Calculate the pending rewards for the wrapper
        uint256 claimable =
            wrapper.pendingRewards + Math.mulDiv(supply, globalIntegral - wrapper.integral, ACCOUNTANT_SCALING_FACTOR);

        // 3. If there are pending rewards, claim them
        if (claimable > 0) {
            address[] memory gauges = new address[](1);
            gauges[0] = GAUGE;
            ACCOUNTANT.claim(gauges, new bytes[](0));
        }

        // 4. Transfer the part of the pending rewards that belongs to the caller
        UserCheckpoint storage userCheckpoint = userCheckpoints[msg.sender];
        amount = _calculatePendingRewards(userCheckpoint);
        if (amount != 0) {
            userCheckpoint.rewardPerTokenPaid[MAIN_REWARD_TOKEN_SLOT] = globalIntegral;
            SafeERC20.safeTransfer(MAIN_REWARD_TOKEN, receiver, amount);
            emit Claimed(address(MAIN_REWARD_TOKEN), msg.sender, receiver, amount);
        }
    }

    /// @notice Claims all the caller's extra reward tokens for himself
    /// @return amounts Array of claimed amounts
    function claimExtraRewards() external nonReentrant returns (uint256[] memory amounts) {
        return _claimExtraRewards(REWARD_VAULT.getRewardTokens(), msg.sender);
    }

    /// @notice Claims the rewards for the given extra reward tokens for the caller
    /// @param tokens Array of extra reward tokens to claim
    /// @return amounts Array of claimed amounts
    function claimExtraRewards(address[] calldata tokens) external nonReentrant returns (uint256[] memory amounts) {
        return _claimExtraRewards(tokens, msg.sender);
    }

    /// @notice Claims the rewards for the given extra reward tokens for the receiver
    /// @param tokens Array of extra reward tokens to claim
    /// @param receiver The address to receive the extra reward tokens
    /// @return amounts Array of claimed amounts
    /// @custom:reverts InvalidTokens if the provided token list is empty
    /// @custom:reverts ZeroAddress if the receiver address is the zero address
    function claimExtraRewards(address[] calldata tokens, address receiver)
        external
        nonReentrant
        returns (uint256[] memory amounts)
    {
        return _claimExtraRewards(tokens, receiver);
    }

    function _claimExtraRewards(address[] memory tokens, address receiver)
        internal
        returns (uint256[] memory amounts)
    {
        require(tokens.length > 0, InvalidTokens());
        require(receiver != address(0), ZeroAddress());

        // 1. Update the reward state for all the extra reward tokens
        _updateExtraRewardState(tokens);

        amounts = new uint256[](tokens.length);
        UserCheckpoint storage checkpoint = userCheckpoints[msg.sender];

        // 2. Calculate the pending rewards for each extra reward token
        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 reward = _calculatePendingExtraRewards(checkpoint, token);

            // 3. If there are pending rewards, update the user's checkpoint and transfer the rewards to the receiver
            if (reward > 0) {
                checkpoint.rewardPerTokenPaid[token] = extraRewardPerToken[token];
                amounts[i] = reward; // Store the claimed amount
                SafeERC20.safeTransfer(IERC20(token), receiver, reward);
                emit Claimed(token, msg.sender, receiver, reward);
            }
        }

        return amounts;
    }

    /// @dev Claims pending main + extra rewards for the caller
    function _claimAllRewards(address receiver) internal {
        // Claim main rewards – will internally pull from Accountant only if needed
        _claim(receiver);

        // Claim all extra rewards
        _claimExtraRewards(REWARD_VAULT.getRewardTokens(), receiver);
    }

    ///////////////////////////////////////////////////////////////
    // --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Calculates the pending amount of main reward token for a user
    /// @param checkpoint The user checkpoint
    /// @return The amount of pending main reward token
    function _calculatePendingRewards(UserCheckpoint storage checkpoint) internal view returns (uint256) {
        uint256 globalIntegral = _getGlobalIntegral();
        uint256 userRewardPerTokenPaid = checkpoint.rewardPerTokenPaid[MAIN_REWARD_TOKEN_SLOT];

        return Math.mulDiv(checkpoint.balance, globalIntegral - userRewardPerTokenPaid, ACCOUNTANT_SCALING_FACTOR);
    }

    /// @notice Calculates the pending amount of a specific extra reward token for a user
    /// @param checkpoint The user checkpoint
    /// @param token The address of the extra reward token
    /// @return The amount of pending extra reward token
    function _calculatePendingExtraRewards(UserCheckpoint storage checkpoint, address token)
        internal
        view
        returns (uint256)
    {
        uint256 currentRewardPerToken = extraRewardPerToken[token];
        uint256 userRewardPerTokenPaid = checkpoint.rewardPerTokenPaid[token];

        return Math.mulDiv(checkpoint.balance, currentRewardPerToken - userRewardPerTokenPaid, 1e18);
    }

    /// @notice Updates the reward state for all the extra reward tokens
    /// @dev    Sweeping hypothetical sleeping rewards would require supply to be non-zero due to the safe early return
    /// @param tokens Array of extra reward tokens to update
    function _updateExtraRewardState(address[] memory tokens) internal {
        // 1. Get the total supply of the wrapped tokens (shares)
        uint256 supply = totalSupply();
        if (supply == 0) return;

        // 2. Claim the rewards from the RewardVault
        uint256[] memory amounts = REWARD_VAULT.claim(tokens, address(this));

        // 3. Update the stored rewards for each extra reward token
        for (uint256 i; i < tokens.length; i++) {
            uint256 amount = amounts[i];
            if (amount > 0) extraRewardPerToken[tokens[i]] += Math.mulDiv(amount, 1e18, supply);
        }
    }

    /// @notice Get the global integral from the Accountant
    /// @return integral The global integral for the RewardVault as stored in the Accountant
    function _getGlobalIntegral() internal view returns (uint256 integral) {
        integral = ACCOUNTANT.vaults(address(REWARD_VAULT)).integral;
    }

    ///////////////////////////////////////////////////////////////
    // --- GETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Calculate the pending amount of main reward token for a user
    /// @param user The address of the user
    /// @return rewards The amount of pending main reward token
    function getPendingRewards(address user) external view returns (uint256 rewards) {
        UserCheckpoint storage checkpoint = userCheckpoints[user];
        rewards = _calculatePendingRewards(checkpoint);
    }

    /// @notice Calculate the pending amount of all the extra reward tokens for a user.
    /// @param user The address of the user
    /// @return rewards The amount of pending rewards
    function getPendingExtraRewards(address user) external view returns (uint256[] memory rewards) {
        address[] memory extraRewardTokens = REWARD_VAULT.getRewardTokens();
        UserCheckpoint storage checkpoint = userCheckpoints[user];
        rewards = new uint256[](extraRewardTokens.length);

        for (uint256 i; i < extraRewardTokens.length; i++) {
            rewards[i] = _calculatePendingExtraRewards(checkpoint, extraRewardTokens[i]);
        }
    }

    /// @notice Calculate the pending amount of a specific extra reward token for a user.
    ///         If you're looking for the pending amount of the main reward token, call `getPendingRewards` instead.
    /// @dev    The only reason to pass the address of the main reward token to this function is if
    ///         the main reward token is also listed as an extra reward token. It can happen in some cases.
    /// @param user The address of the user
    /// @param token The address of the extra reward token
    /// @return rewards The amount of pending rewards
    /// @custom:reverts ZeroAddress if the token address is the main reward token address (address(0))
    function getPendingExtraRewards(address user, address token) external view returns (uint256 rewards) {
        require(token != MAIN_REWARD_TOKEN_SLOT, ZeroAddress());

        UserCheckpoint storage checkpoint = userCheckpoints[user];
        rewards = _calculatePendingExtraRewards(checkpoint, token);
    }

    /// @notice Get the decimals of the wrapped token
    /// @return The decimals of the wrapped token
    function decimals() public view override(IERC20Metadata, ERC20) returns (uint8) {
        return REWARD_VAULT.decimals();
    }

    /// @dev Get the name of the token
    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return string.concat(REWARD_VAULT.name(), " wrapped");
    }

    /// @dev Get the symbol of the token
    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return string.concat(REWARD_VAULT.symbol(), "-wrapped");
    }

    /// @notice Returns the current version of this contract.
    /// @return version The version of the contract.
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
