// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IStrategyWrapper} from "src/interfaces/IStrategyWrapper.sol";
import {IMorpho, Id} from "shared/src/morpho/IMorpho.sol";

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
    // --- IMMUTABLES/CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice The slot of the main reward token in the user checkpoint
    /// @dev    In order to optimize the storage, the main reward token is tracked in the same
    ///         mapping as the extra reward tokens by using the `address(0)` slot.
    ///         This internal value that is never supposed to be exposed must be used to read/write
    ///         the main reward token state.
    /// @dev    `address(0)` has been chosen to avoid collisions with the extra reward tokens.
    address internal constant MAIN_REWARD_TOKEN_SLOT = address(0);

    /// @notice Gauge backing the wrapped RewardVault
    address internal immutable GAUGE;

    /// @notice The address of the accountant contract
    IAccountant internal immutable ACCOUNTANT;

    /// @dev Precision used by Accountant.integral (usually 1e27)
    uint128 internal immutable ACCOUNTANT_SCALING_FACTOR;

    /// @notice The address of the token that is being wrapped
    IRewardVault public immutable REWARD_VAULT;

    /// @notice The address of the lending protocol
    address public immutable LENDING_PROTOCOL;

    /// @notice Reward token emitted by the Accountant (e.g. CRV)
    IERC20 public immutable MAIN_REWARD_TOKEN;

    /// @notice Tracks user deposit data and reward checkpoints
    /// @param balance User's wrapped-share balance
    /// @param rewardPerTokenPaid Last per-token accumulator seen
    struct UserCheckpoint {
        uint256 balance;
        mapping(address token => uint256 amount) rewardPerTokenPaid;
    }

    /// @notice The ID of the lending market this token is expected to interact with
    bytes32 public lendingMarketId;

    /// @notice User checkpoint data including his deposit balance and the amount of rewards he has claimed for each token
    ///         Both the main reward token and the extra reward tokens are tracked in the same mapping.
    /// @dev    The main reward token is tracked in `rewardPerTokenPaid[address(0)]`
    mapping(address user => UserCheckpoint checkpoint) private userCheckpoints;

    /// @notice Accumulated rewards per token. Track the extra reward tokens only.
    /// @dev    The main reward token is tracked by fetching the latest value from the Accountant.
    mapping(address token => uint256 amount) public extraRewardPerToken;

    /// @dev The purpose of this transient variable is to ensure that this token can only be
    /// used as collateral in the predefined lending market. When this variable is set to
    /// false (the default value), transfers to the lending protocol are unauthorized.
    /// The only way to change this variable to true is by entering the flow of the deposit
    /// functions in this contract.
    bool private transient depositUnlocked;

    ///////////////////////////////////////////////////////////////
    // --- EVENTS/ERRORS
    ///////////////////////////////////////////////////////////////

    event Claimed(address indexed token, address indexed account, uint256 amount);
    event Deposited(address indexed user, uint256 amount, bytes32 marketId);
    event Withdrawn(address indexed user, uint256 amount);
    event Liquidated(address indexed liquidator, address indexed victim, uint256 amount);
    event MarketAdded(bytes32 marketId);

    error ZeroAmount();
    error ZeroAddress();
    error InvalidTokens();
    error InvalidMarket();
    error MarketAlreadySet();
    error WrapperNotInitialized();
    error InvalidLiquidation();
    /// @dev Only the lending protocol can transfer in/out the wrapped tokens
    error TransferUnauthorized();
    /// @dev Deposit collateral to the lending protocol is only allowed through the StrategyWrapperContract
    ///      Do not interact directly with the lending protocol to deposit collateral. Instead, call one of the `deposit`
    ///      functions defined in the StrategyWrapperContract instead.
    error InvalidDepositFlow();

    /// @param rewardVault The reward vault contract
    /// @param lendingProtocol The lending protocol contract
    /// @param _owner The owner of the contract
    /// @custom:reverts ZeroAddress if the reward vault or _owner address are the zero address
    constructor(IRewardVault rewardVault, address lendingProtocol, address _owner) ERC20("", "") Ownable(_owner) {
        require(
            address(rewardVault) != address(0) && lendingProtocol != address(0) && _owner != address(0), ZeroAddress()
        );

        IAccountant accountant = rewardVault.ACCOUNTANT();

        // Store the immutable variables
        GAUGE = rewardVault.gauge();
        ACCOUNTANT = accountant;
        REWARD_VAULT = rewardVault;
        MAIN_REWARD_TOKEN = IERC20(accountant.REWARD_TOKEN());
        ACCOUNTANT_SCALING_FACTOR = accountant.SCALING_FACTOR();
        LENDING_PROTOCOL = lendingProtocol;

        // Approve the asset token to the reward vault and the wrapped token to the lending protocol
        SafeERC20.forceApprove(IERC20(rewardVault.asset()), address(rewardVault), type(uint256).max);
        _approve(address(this), lendingProtocol, type(uint256).max, true);
    }

    ///////////////////////////////////////////////////////////////
    // --- INITIALIZATION
    ///////////////////////////////////////////////////////////////

    /// @notice Set the market ID for the wrapper
    /// @param marketId The ID of the market to set
    /// @custom:reverts MarketAlreadySet if the market ID is already set
    /// @custom:reverts InvalidMarket if the market ID is the invalid
    function initialize(bytes32 marketId) external onlyOwner {
        require(lendingMarketId == bytes32(0), MarketAlreadySet());
        require(marketId != bytes32(0), InvalidMarket());

        // Check that this contract is the collateral of the given market
        require(
            IMorpho(LENDING_PROTOCOL).idToMarketParams(Id.wrap(marketId)).collateralToken == address(this),
            InvalidMarket()
        );

        lendingMarketId = marketId;
        emit MarketAdded(marketId);
    }

    modifier onlyInitialized() {
        require(lendingMarketId != bytes32(0), WrapperNotInitialized());
        _;
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
    function depositShares(uint256 amount) public nonReentrant onlyInitialized {
        require(amount > 0, ZeroAmount());

        // 1. Transfer caller's shares to this contract (checkpoint)
        SafeERC20.safeTransferFrom(IERC20(address(REWARD_VAULT)), msg.sender, address(this), amount);

        _deposit(msg.sender, amount);
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
    function depositAssets(uint256 amount) public nonReentrant onlyInitialized {
        require(amount > 0, ZeroAmount());

        // 1. Get RewardVault's shares by depositing the underlying protocol LP tokens (checkpoint)
        SafeERC20.safeTransferFrom(IERC20(REWARD_VAULT.asset()), msg.sender, address(this), amount);
        uint256 shares = REWARD_VAULT.deposit(amount, address(this), address(this));

        _deposit(msg.sender, shares);
    }

    function _deposit(address account, uint256 amount) internal {
        // 1. Update the user checkpoint
        _updateUserCheckpoint(account, amount);

        // 2. Mint wrapped tokens (1:1)
        _update(address(0), address(this), amount);

        // 3. Supply the minted tokens as collateral to the expected lending market
        depositUnlocked = true;
        IMorpho(LENDING_PROTOCOL).supplyCollateral(
            IMorpho(LENDING_PROTOCOL).idToMarketParams(Id.wrap(lendingMarketId)), amount, account, ""
        );
        depositUnlocked = false;

        emit Deposited(account, amount, lendingMarketId);
    }

    ///////////////////////////////////////////////////////////////
    // --- WITHDRAW
    ///////////////////////////////////////////////////////////////

    /// @notice Withdraws all the assets and claims pending rewards for the caller
    function withdraw() external {
        withdraw(balanceOf(msg.sender));
    }

    /// @notice Withdraws the given amount of assets and claims main/extra pending rewards
    /// @param amount Amount of wrapped tokens to burn
    /// @custom:reverts ZeroAmount if the given amount is zero
    function withdraw(uint256 amount) public nonReentrant {
        require(amount > 0, ZeroAmount());

        // 1. Claim all the pending rewards (main + extra)
        _claimAllRewards(msg.sender);

        // 2. Update the internal user checkpoint
        UserCheckpoint storage checkpoint = userCheckpoints[msg.sender];
        checkpoint.balance -= amount;

        // 4. Burn caller's wrapped tokens
        _burn(msg.sender, amount);

        // 5. Transfer the underlying RewardVault shares back to the caller
        SafeERC20.safeTransfer(IERC20(address(REWARD_VAULT)), msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    ///////////////////////////////////////////////////////////////
    // --- CLAIM
    ///////////////////////////////////////////////////////////////

    /// @notice Claims the caller's main reward token for himself
    /// @return amount Amount of main reward tokens claimed
    function claim() external nonReentrant returns (uint256 amount) {
        return _claim(msg.sender);
    }

    function _claim(address account) internal returns (uint256 amount) {
        require(account != address(0), ZeroAddress());

        // 1. Pull the latest data from the Accountant and the total supply of the wrapper
        IAccountant.AccountData memory wrapper = ACCOUNTANT.accounts(address(REWARD_VAULT), address(this));
        uint256 globalIntegral = _getGlobalIntegral();
        uint256 supply = totalSupply();

        // 2. Calculate the pending rewards for the wrapper
        uint256 claimable =
            wrapper.pendingRewards + Math.mulDiv(supply, globalIntegral - wrapper.integral, ACCOUNTANT_SCALING_FACTOR);

        // 3. If there are some pending rewards, claim them
        if (claimable > 0) {
            address[] memory gauges = new address[](1);
            gauges[0] = GAUGE;
            ACCOUNTANT.claim(gauges, new bytes[](0));
        }

        // 4. Transfer the part of the pending rewards that belongs to the account
        UserCheckpoint storage userCheckpoint = userCheckpoints[account];
        amount = _calculatePendingRewards(userCheckpoint);
        if (amount != 0) {
            userCheckpoint.rewardPerTokenPaid[MAIN_REWARD_TOKEN_SLOT] = globalIntegral;
            // ! safeTransfer would allow the account to block liquidation
            MAIN_REWARD_TOKEN.transfer(account, amount);
            emit Claimed(address(MAIN_REWARD_TOKEN), account, amount);
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

    function _claimExtraRewards(address[] memory tokens, address account) internal returns (uint256[] memory amounts) {
        require(tokens.length > 0, InvalidTokens());
        require(account != address(0), ZeroAddress());

        // 1. Update the reward state for all the extra reward tokens
        _updateExtraRewardState(tokens);

        amounts = new uint256[](tokens.length);
        UserCheckpoint storage checkpoint = userCheckpoints[account];

        // 2. Calculate the pending rewards for each extra reward token
        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 reward = _calculatePendingExtraRewards(checkpoint, token);

            // 3. If there are pending rewards, update the user's checkpoint and transfer the rewards to the account
            if (reward > 0) {
                checkpoint.rewardPerTokenPaid[token] = extraRewardPerToken[token];
                amounts[i] = reward; // Store the claimed amount
                // ! safeTransfer would allow the account to block liquidation
                ERC20(token).transfer(account, reward);
                emit Claimed(token, account, reward);
            }
        }

        return amounts;
    }

    /// @notice Claims pending main + extra rewards for the account
    function _claimAllRewards(address account) internal {
        _claim(account);
        _claimExtraRewards(REWARD_VAULT.getRewardTokens(), account);
    }

    ///////////////////////////////////////////////////////////////
    // --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Updates the user checkpoint with the new deposit amount
    function _updateUserCheckpoint(address account, uint256 amount) internal {
        // 1. Update the internal account checkpoint
        UserCheckpoint storage checkpoint = userCheckpoints[account];
        if (checkpoint.balance != 0) _claimAllRewards(account);
        checkpoint.balance += amount;

        // 2. Keep track of the Main reward token checkpoint
        checkpoint.rewardPerTokenPaid[MAIN_REWARD_TOKEN_SLOT] = _getGlobalIntegral();

        // 3. Keep track of the Extra reward tokens checkpoints at deposit time
        address[] memory rewardTokens = REWARD_VAULT.getRewardTokens();
        _updateExtraRewardState(rewardTokens);
        for (uint256 i; i < rewardTokens.length; i++) {
            checkpoint.rewardPerTokenPaid[rewardTokens[i]] = extraRewardPerToken[rewardTokens[i]];
        }
    }
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
        uint256 supply = totalSupply();
        if (supply == 0) return 0;

        uint256 currentRewardPerToken = extraRewardPerToken[token];
        uint256 newRewards = uint256(REWARD_VAULT.earned(address(this), token));
        if (newRewards > 0) currentRewardPerToken += Math.mulDiv(newRewards, 1e18, supply);

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
    // --- TRANSFER
    ///////////////////////////////////////////////////////////////

    /// @dev Only the lending protocol can transfer in/out the wrapped tokens
    function transfer(address to, uint256 value) public virtual override(IERC20, ERC20) returns (bool) {
        require(msg.sender == LENDING_PROTOCOL, TransferUnauthorized());
        return super.transfer(to, value);
    }

    /// @dev Only the lending protocol can transfer in/out the wrapped tokens
    function transferFrom(address from, address to, uint256 value)
        public
        virtual
        override(IERC20, ERC20)
        returns (bool)
    {
        require(msg.sender == LENDING_PROTOCOL, TransferUnauthorized());

        // Only authorize deposits to the lending protocol when the deposit is made through this contract
        if (to == LENDING_PROTOCOL) require(depositUnlocked == true, InvalidDepositFlow());

        return super.transferFrom(from, to, value);
    }

    ///////////////////////////////////////////////////////////////
    // --- LIQUIDATION
    ///////////////////////////////////////////////////////////////

    /// @notice Claims liquidation rights after receiving tokens from a liquidation event on the lending protocol
    /// @param liquidator The address that received the liquidated tokens from Morpho
    /// @param victim The address whose position was liquidated
    /// @param liquidatedAmount The exact amount of tokens that were seized during liquidation
    ///
    /// @dev This function MUST be called by liquidators after receiving wrapped tokens from a liquidation to receive
    ///      the liquidated amount of underlying RewardVault shares.
    ///      Without calling this function, liquidators will:
    ///      - Be unable to withdraw tokens (will revert due to insufficient internal balance)
    ///      - Leave the victim earning rewards on tokens they no longer own
    /// Example:
    ///   1. Alice has 1000 wrapped tokens used as collateral in Morpho
    ///   2. Bob liquidates Alice's position, receiving 300 tokens from Morpho
    ///   3. Bob's state: ERC20 balance = 300, internal balance = 0 (off-track!)
    ///   4. Bob calls: claimLiquidation(bob, alice, 300)
    ///   5. Result: Bob received 300 underlying RewardVault shares, Alice stops earning on liquidated amount
    ///
    /// @dev This function must also be called if you withdraw your collateral on the lending protocol to a
    /// different receiver. We advise against this scenario and recommend withdrawing your collateral to the
    /// same receiver who deposited it. However, if you choose to proceed, you must call this function to
    /// re-synchronize the internal accountability. In this case, the liquidator will be the receiver of
    /// the collateral, while the victim will be the one who deposited it. From the perspective of this
    /// contract, withdrawing to a different receiver is equivalent to liquidation.
    /// Example:
    ///   1. Alice has 1000 wrapped tokens used as collateral in Morpho
    ///   2. Alice withdraws her collateral to Bob, receiving 1000 tokens from Morpho
    ///   3. Bob's state: ERC20 balance = 1000, internal balance = 0 (off-track!)
    ///   4. Bob calls: claimLiquidation(bob, alice, 1000)
    ///   5. Result: Bob received 1000 underlying RewardVault shares, Alice stops earning on liquidated amount
    function claimLiquidation(address liquidator, address victim, uint256 liquidatedAmount) external nonReentrant {
        require(liquidator != address(0) && victim != address(0), ZeroAddress());
        require(liquidatedAmount > 0, ZeroAmount());

        // 1. Check that the liquidator own the claimed amount and that it's off-track
        //    Because token is untransferable (except by the lending protocol), the only way
        //    to have an off-track balance is to get it from liquidation executed by the lending protocol.
        //    We have to be sure the claimed amount is off-track, otherwise any holders will be able to liquidate any positions.
        require(balanceOf(liquidator) >= userCheckpoints[liquidator].balance + liquidatedAmount, InvalidLiquidation());

        // 2. Check that the victim has enough tokens registered internally
        uint256 internalVictimBalance = userCheckpoints[victim].balance;
        require(internalVictimBalance >= liquidatedAmount, InvalidLiquidation());

        // 3. Check that the victim as a real holding hole of at least the claimed amount
        //    This is done by summing up the collateral supplied by the victim with his balance.
        //    Because token is untransferable (except by the lending protocol), the only way
        //    to have an off-track balance is to get liquidated.
        uint256 victimBalance =
            balanceOf(victim) + IMorpho(LENDING_PROTOCOL).position(Id.wrap(lendingMarketId), victim).collateral;
        require(internalVictimBalance - victimBalance >= liquidatedAmount, InvalidLiquidation());

        // 4. Claim the accrued rewards for the victim and reduce his internal balance
        _claimAllRewards(victim);
        userCheckpoints[victim].balance -= liquidatedAmount;

        // 5. Burn the liquidated amount and transfer the underlying RewardVault shares back to the liquidator
        _burn(liquidator, liquidatedAmount);
        SafeERC20.safeTransfer(IERC20(address(REWARD_VAULT)), liquidator, liquidatedAmount);

        emit Liquidated(liquidator, victim, liquidatedAmount);
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
    function name() public view override(IERC20Metadata, ERC20) onlyInitialized returns (string memory) {
        IERC20Metadata loanToken =
            IERC20Metadata(IMorpho(LENDING_PROTOCOL).idToMarketParams(Id.wrap(lendingMarketId)).loanToken);
        return string.concat(REWARD_VAULT.name(), " wrapped for", loanToken.name());
    }

    /// @dev Get the symbol of the token
    function symbol() public view override(IERC20Metadata, ERC20) onlyInitialized returns (string memory) {
        IERC20Metadata loanToken =
            IERC20Metadata(IMorpho(LENDING_PROTOCOL).idToMarketParams(Id.wrap(lendingMarketId)).loanToken);
        return string.concat(REWARD_VAULT.symbol(), "-wrapped-", loanToken.symbol());
    }
}
