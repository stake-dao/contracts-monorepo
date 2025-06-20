// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IMorphoStrategyWrapper} from "src/interfaces/IMorphoStrategyWrapper.sol";

/// @title Stake DAO Morpho Strategy Wrapper
/// @notice ERC20 wrapper for Stake DAO RewardVault shares, designed for use as non-transferable collateral in Morpho lending markets.
/// @dev Handles reward claiming and distribution for the initial owner while shares are locked as collateral
/// @dev   - Allows users to deposit RewardVault shares and receive non-transferable tokens (1:1)
///        - While the ERC20 tokens are held (even as collateral in Morpho), users can claim both main protocol rewards and extra rewards
///        - Handles the edge case where the main reward token is also listed as an extra reward
///        - Integrates with Stake DAO's reward and checkpointing logic to ensure users always receive the correct rewards, regardless of the custody
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
/// @custom:github https://github.com/stake-dao/contracts-monorepo
contract MorphoStrategyWrapper is ERC20, IMorphoStrategyWrapper, ReentrancyGuardTransient {
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

    /// @notice The Morpho market contract address
    address public immutable MORPHO;

    /// @dev Precision used by Accountant.integral (usually 1e27)
    uint128 public immutable ACCOUNTANT_SCALING_FACTOR;

    ///////////////////////////////////////////////////////////////
    // --- STATE
    ///////////////////////////////////////////////////////////////

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

    /// @dev Thrown when non-Morpho tries to transfer wrapped tokens
    error OnlyMorpho();

    /// @dev Thrown when a given amount is zero
    error ZeroAmount();

    /// @dev Thrown when a given address is the zero address
    error ZeroAddress();

    /// @dev Thrown when the provided token list is empty
    error InvalidTokens();

    /// @param rewardVault The address of the reward vault contract
    /// @param morpho The address of the Morpho contract
    /// @custom:reverts ZeroAddress if the reward vault or Morpho address is the zero address
    constructor(IRewardVault rewardVault, address morpho) ERC20("", "") {
        require(address(rewardVault) != address(0) && morpho != address(0), ZeroAddress());

        IAccountant accountant = rewardVault.ACCOUNTANT();

        // Store the immutable variables
        GAUGE = rewardVault.gauge();
        ACCOUNTANT = accountant;
        MORPHO = morpho;
        REWARD_VAULT = rewardVault;
        MAIN_REWARD_TOKEN = IERC20(accountant.REWARD_TOKEN());
        ACCOUNTANT_SCALING_FACTOR = accountant.SCALING_FACTOR();
    }

    ///////////////////////////////////////////////////////////////
    // --- DEPOSIT
    ///////////////////////////////////////////////////////////////

    /// @notice Deposits all the RewardVault shares and mints wrapped tokens for the caller
    function deposit() external {
        deposit(REWARD_VAULT.balanceOf(msg.sender));
    }

    /// @notice Deposits `amount` RewardVault shares and mints the same amount of wrapper tokens to the caller
    /// @param amount Amount of shares to deposit
    /// @custom:reverts ZeroAmount if the given amount is zero
    function deposit(uint256 amount) public {
        require(amount > 0, ZeroAmount());

        // 1. Transfer caller's shares to this contract (trigger the checkpoint action in the RewardVault)
        SafeERC20.safeTransferFrom(IERC20(address(REWARD_VAULT)), msg.sender, address(this), amount);

        // 2. Update the internal user checkpoint
        UserCheckpoint storage checkpoint = userCheckpoints[msg.sender];
        checkpoint.balance += amount;

        // 3. Keep track of the Main reward token checkpoint
        checkpoint.rewardPerTokenPaid[MAIN_REWARD_TOKEN_SLOT] = _getGlobalIntegral();

        // 4. Keep track of the Extra reward tokens checkpoints at deposit time
        address[] memory rewardTokens = REWARD_VAULT.getRewardTokens();
        for (uint256 i; i < rewardTokens.length; i++) {
            checkpoint.rewardPerTokenPaid[rewardTokens[i]] = extraRewardPerToken[rewardTokens[i]];
        }

        // 5. Mint wrapped tokens (1:1) for the caller
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
    function withdraw(uint256 amount, address receiver) public {
        require(amount > 0, ZeroAmount());
        require(receiver != address(0), ZeroAddress());

        // 1. Claim main rewards for the receiver
        claim(receiver);

        // 2. Claim all the pending extra rewards for the receiver
        claimExtraRewards(REWARD_VAULT.getRewardTokens(), receiver);

        // 3. Update the internal user checkpoint
        UserCheckpoint storage checkpoint = userCheckpoints[msg.sender];
        checkpoint.balance -= amount;

        // 4. Burn caller's wrapped tokens
        _burn(msg.sender, amount);

        // 5. Transfer the underlying RewardVault shares back to the receiver
        SafeERC20.safeTransfer(IERC20(address(REWARD_VAULT)), receiver, amount);

        emit Withdrawn(msg.sender, receiver, amount);
    }

    ///////////////////////////////////////////////////////////////
    // --- CLAIM MAIN REWARDS
    ///////////////////////////////////////////////////////////////

    /// @notice Claims the caller's main reward token for himself
    /// @return amount Amount of main reward tokens claimed
    function claim() external returns (uint256 amount) {
        return claim(msg.sender);
    }

    /// @notice Claims the caller's main reward token for the receiver
    /// @param receiver The address to receive the main reward tokens
    /// @return amount Amount of main reward tokens claimed
    /// @custom:reverts ZeroAddress if the receiver address is the zero address
    function claim(address receiver) public nonReentrant returns (uint256 amount) {
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

    ///////////////////////////////////////////////////////////////
    // --- CLAIM EXTRA REWARDS
    ///////////////////////////////////////////////////////////////

    /// @notice Claims all the caller's extra reward tokens for himself
    /// @return amounts Array of claimed amounts
    function claimExtraRewards() external returns (uint256[] memory amounts) {
        return claimExtraRewards(REWARD_VAULT.getRewardTokens(), msg.sender);
    }

    /// @notice Claims the rewards for the given extra reward tokens for the caller
    /// @param tokens Array of extra reward tokens to claim
    /// @return amounts Array of claimed amounts
    function claimExtraRewards(address[] calldata tokens) public returns (uint256[] memory amounts) {
        return claimExtraRewards(tokens, msg.sender);
    }

    /// @notice Claims the rewards for the given extra reward tokens for the receiver
    /// @param tokens Array of extra reward tokens to claim
    /// @param receiver The address to receive the extra reward tokens
    /// @return amounts Array of claimed amounts
    /// @custom:reverts InvalidTokens if the provided token list is empty
    /// @custom:reverts ZeroAddress if the receiver address is the zero address
    function claimExtraRewards(address[] memory tokens, address receiver)
        public
        nonReentrant
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
    // --- ERC-20 OVERRIDEN FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Restricts the transfer to Morpho only
    /// @dev Only Morpho can transfer the wrapped tokens. The token isn't liquid.
    /// @param to The address to transfer the tokens to
    /// @param amount The amount of tokens to transfer
    /// @return True if the transfer is successful
    /// @custom:reverts OnlyMorpho if the sender is not Morpho
    function transfer(address to, uint256 amount) public override(IERC20, ERC20) returns (bool) {
        require(msg.sender == MORPHO, OnlyMorpho());
        return super.transfer(to, amount);
    }

    /// @notice Restricts the transferFrom to Morpho only
    /// @dev Only Morpho can transfer the wrapped tokens. The token isn't liquid.
    /// @param from The address to transfer the tokens from
    /// @param to The address to transfer the tokens to
    /// @param amount The amount of tokens to transfer
    /// @return True if the transfer is successful
    /// @custom:reverts OnlyMorpho if the sender is not Morpho
    function transferFrom(address from, address to, uint256 amount) public override(IERC20, ERC20) returns (bool) {
        require(msg.sender == MORPHO, OnlyMorpho());
        return super.transferFrom(from, to, amount);
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
        return string.concat(REWARD_VAULT.name(), " Morpho");
    }

    /// @dev Get the symbol of the token
    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return string.concat(REWARD_VAULT.symbol(), "-morpho");
    }

    /// @notice Returns the current version of this contract.
    /// @return version The version of the contract.
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
