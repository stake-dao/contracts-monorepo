// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISidecar} from "src/interfaces/ISidecar.sol";
import {IAccountant} from "src/interfaces/IAccountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title Sidecar - Alternative yield source manager alongside main locker
/// @notice Base contract for protocol-specific yield sources that complement the main locker strategy
/// @dev Design rationale:
///      - Enables yield diversification beyond the main protocol locker (e.g., Convex alongside veCRV)
///      - Protocol-agnostic base allows extension for any yield source
///      - Managed by Strategy for unified deposit/withdraw/harvest operations
///      - Rewards flow through Accountant for consistent distribution
abstract contract Sidecar is ISidecar {
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    // --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice Protocol identifier matching the Strategy that manages this sidecar
    bytes4 public immutable PROTOCOL_ID;

    /// @notice Accountant that receives and distributes rewards from this sidecar
    address public immutable ACCOUNTANT;

    /// @notice Main protocol reward token claimed by this sidecar (e.g., CRV)
    IERC20 public immutable REWARD_TOKEN;

    /// @notice Registry used to verify the authorized strategy for this protocol
    IProtocolController public immutable PROTOCOL_CONTROLLER;

    //////////////////////////////////////////////////////
    // --- STORAGE
    //////////////////////////////////////////////////////

    /// @notice Prevents double initialization in factory deployment pattern
    bool private _initialized;

    //////////////////////////////////////////////////////
    // --- ERRORS
    //////////////////////////////////////////////////////

    error ZeroAddress();

    error OnlyStrategy();

    error OnlyAccountant();

    error AlreadyInitialized();

    error NotInitialized();

    error InvalidProtocolId();

    //////////////////////////////////////////////////////
    // --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Restricts access to the authorized strategy for this protocol
    /// @dev Prevents unauthorized manipulation of user funds
    modifier onlyStrategy() {
        require(PROTOCOL_CONTROLLER.strategy(PROTOCOL_ID) == msg.sender, OnlyStrategy());
        _;
    }

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Sets up immutable protocol connections
    /// @dev Called by factory during deployment. Reward token fetched from accountant
    /// @param _protocolId Protocol identifier for strategy verification
    /// @param _accountant Where to send claimed rewards for distribution
    /// @param _protocolController Registry for strategy lookup and validation
    constructor(bytes4 _protocolId, address _accountant, address _protocolController) {
        require(_protocolId != bytes4(0), InvalidProtocolId());
        require(_accountant != address(0) && _protocolController != address(0), ZeroAddress());

        PROTOCOL_ID = _protocolId;
        ACCOUNTANT = _accountant;
        PROTOCOL_CONTROLLER = IProtocolController(_protocolController);
        REWARD_TOKEN = IERC20(IAccountant(_accountant).REWARD_TOKEN());

        _initialized = true;
    }

    //////////////////////////////////////////////////////
    // --- EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice One-time setup for protocol-specific configuration
    /// @dev Factory pattern: minimal proxy clones need post-deployment init
    ///      Base constructor sets _initialized=true, clones must call this
    function initialize() external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        _initialize();
    }

    /// @notice Stakes LP tokens into the protocol-specific yield source
    /// @dev Strategy transfers tokens here first, then calls deposit
    /// @param amount LP tokens to stake (must already be transferred)
    function deposit(uint256 amount) external onlyStrategy {
        _deposit(amount);
    }

    /// @notice Unstakes LP tokens and sends directly to receiver
    /// @dev Used during user withdrawals and emergency shutdowns
    /// @param amount LP tokens to unstake from yield source
    /// @param receiver Where to send the unstaked tokens (vault or user)
    function withdraw(uint256 amount, address receiver) external onlyStrategy {
        _withdraw(amount, receiver);
    }

    /// @notice Harvests rewards and transfers to accountant
    /// @dev Part of Strategy's harvest flow. Returns amount for accounting
    /// @return Amount of reward tokens sent to accountant
    function claim() external onlyStrategy returns (uint256) {
        return _claim();
    }

    //////////////////////////////////////////////////////
    // --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice LP token this sidecar manages (e.g., CRV/ETH LP)
    /// @dev Must match the asset used by the associated Strategy
    function asset() public view virtual returns (IERC20);

    /// @notice Where extra rewards (not main protocol rewards) should be sent
    /// @dev Typically the RewardVault for the gauge this sidecar supports
    function rewardReceiver() public view virtual returns (address);

    //////////////////////////////////////////////////////
    // --- INTERNAL VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @dev Protocol-specific setup (approvals, staking contracts, etc.)
    function _initialize() internal virtual;

    /// @dev Stakes tokens in protocol-specific way (e.g., Convex deposit)
    /// @param amount Tokens to stake (already transferred to this contract)
    function _deposit(uint256 amount) internal virtual;

    /// @dev Claims all available rewards and transfers to accountant
    /// @return Total rewards claimed and transferred
    function _claim() internal virtual returns (uint256);

    /// @dev Unstakes from protocol and sends tokens to receiver
    /// @param amount Tokens to unstake
    /// @param receiver Destination for unstaked tokens
    function _withdraw(uint256 amount, address receiver) internal virtual;

    /// @notice Total LP tokens staked in this sidecar
    /// @dev Used by Strategy to calculate total assets across all sources
    /// @return Current staked balance
    function balanceOf() public view virtual returns (uint256);

    /// @notice Unclaimed rewards available for harvest
    /// @dev May perform view-only simulation or on-chain checkpoint
    /// @return Claimable reward token amount
    function getPendingRewards() public virtual returns (uint256);
}
