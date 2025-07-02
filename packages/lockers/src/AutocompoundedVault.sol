// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title Autocompounded Staking ERC4626 Vault
/// @notice
///   This contract is a fully compliant ERC4626 yield-bearing vault with streaming rewards that supports integrated staking.
///   - User deposits are staked into an external protocol (e.g., a gauge or staking contract) to earn additional yield.
///   - Staking rewards are streamed linearly over a fixed period, providing predictable and fair distribution to users.
///   - The vault is designed to be protocol-agnostic: staking, unstaking, and reward-claiming logic are implemented in derived contracts.
///
/// @dev
///   Streaming Reward Policy:
///     - If a new stream is started before the previous one ends, any unvested rewards from the previous stream
///       are automatically rolled over and added to the new stream amount. The combined total is then streamed
///       linearly over the new period.
///     - For optimal and fair reward distribution, it is strongly recommended to start a new stream only after
///       the previous stream has ended, or as close as possible to its scheduled end time.
///     - Starting new streams prematurely can lead to accelerated vesting and may distort the intended reward schedule.
///     - This design is a trade-off for simplicity and to keep the reward calendar predictable and aligned.
///
///   Staking Integration:
///     - On deposit, assets are staked into an external contract for yield generation.
///     - On withdrawal, assets are unstaked as needed before being returned to the user.
///     - The vault tracks both staked assets and the vested portion of any rewards being streamed.
///     - Staking/unstaking/reward-claiming logic is abstract and must be implemented in protocol-specific child contracts.
///
///   ERC4626 Virtual Shares/Assets Protection:
///     - This contract inherits from OpenZeppelin's v5 ERC4626, which implements the "virtual shares/assets" protection mechanism.
///     - This mechanism applies a +1 virtual offset to both totalSupply and totalAssets in the share/asset conversion formulas:
///         - shares = assets/// (totalSupply() + 1) / (totalAssets() + 1)
///         - assets = shares/// (totalAssets() + 1) / (totalSupply() + 1)
///     - With this configuration, the protection ensures that donation/inflation attacks are unprofitable.
///     - Even with a decimal offset of 0, the attacker's loss is at least equal to the user's deposit, as documented by OpenZeppelin.
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
abstract contract AutocompoundedVault is ERC4626, Ownable2Step {
    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice The duration the rewards are streamed over
    uint128 public immutable STREAMING_PERIOD;

    ////////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////

    /// @notice The account responsible of managing the stream of rewards
    address public manager;

    /// @notice The struct holding the stream data
    /// @dev This struct takes 2 storage slots
    struct Stream {
        uint256 amount; // The amount of asset tokens streamed over the period
        uint128 start; // The start timestamp of the stream
        uint128 end; // The end timestamp of the stream
    }

    /// @notice The current active stream
    Stream internal currentStream;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when a new stream is started
    event NewStreamRewards(address indexed caller, uint256 amount, uint128 start, uint128 end);

    /// @notice Event emitted when the manager of the vault changes
    /// @param newManager The new manager of the vault
    event ManagerChanged(address indexed newManager);

    /// @notice Error thrown when the caller is not the manager of the vault
    error InvalidManager();

    ////////////////////////////////////////////////////////////////
    /// --- MODIFIERS & CONSTRUCTOR
    ///////////////////////////////////////////////////////////////

    /// @notice Modifier to check if the caller is the manager of the vault
    modifier onlyManager() {
        if (msg.sender != manager) revert InvalidManager();
        _;
    }

    /// @notice Initialize the asset and the shares token
    /// @param streamingPeriod The streaming period in seconds (e.g. 7 days)
    /// @param asset The asset token the users will deposit to the vault (e.g. sdYND)
    /// @param shareName The name of the shares token the users will receive
    /// @param shareSymbol The symbol of the shares token the users will receive
    /// @param owner The owner of the vault
    /// @param _manager The manager of the vault
    constructor(
        uint128 streamingPeriod,
        IERC20 asset,
        string memory shareName,
        string memory shareSymbol,
        address owner,
        address _manager
    ) ERC4626(asset) ERC20(shareName, shareSymbol) Ownable(owner) {
        STREAMING_PERIOD = streamingPeriod;

        _setManager(_manager);
    }

    ////////////////////////////////////////////////////////////////
    /// --- OVERRIDED ERC4626 FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Stake the deposit assets immediately after the deposit and share minting operation.
    /// @dev This function is called by the ERC4626 `mint` and `deposit` functions during the deposit operation
    /// @param caller The address that called the deposit function
    /// @param receiver The address that will receive the shares
    /// @param assets The amount of assets deposited
    /// @param shares The amount of shares minted
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        super._deposit(caller, receiver, assets, shares);
        _stake(assets);
    }

    /// @notice Unstake the deposit assets before the operation of withdrawal.
    /// @dev This function is called by the ERC4626 `redeem` and `withdraw` functions during the withdrawal operation
    /// @param caller The address that called the withdraw function
    /// @param receiver The address that will receive the assets
    /// @param owner The address that owns the shares
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of shares to burn
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        _unstake(assets);
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Returns the total vested (withdrawable) assets for ERC4626 calculations
    /// @dev In this model, all assets (including rewards) are always staked in the external contract (e.g., gauge).
    ///      Only the vested portion of the staked balance is considered withdrawable by users; the unvested portion remains locked.
    ///      - If there is no active stream, or if the current stream has ended, returns the full staked balance.
    ///      - If the stream is active, subtracts the unvested portion (linearly vesting) from the staked balance.
    ///      - The unvested portion is calculated as the remaining time in the stream over the total stream duration.
    /// @return The total amount of vested (withdrawable) asset tokens, as used by ERC4626 for deposit/withdrawal calculations.
    function totalAssets() public view virtual override returns (uint256) {
        uint256 staked = _getStakedBalance();
        Stream storage stream = currentStream;
        uint128 currentTimestamp = _timestamp();

        // If there is no stream or the stream ended, all staked assets are vested
        if (currentTimestamp >= stream.end) return staked;

        // If the stream is active, subtract the unvested portion from the staked balance
        uint128 remainingTime = stream.end - currentTimestamp;
        uint128 streamDuration = stream.end - stream.start;
        uint256 unvested = stream.amount * remainingTime / streamDuration;
        return staked - unvested;
    }

    ////////////////////////////////////////////////////////////////
    /// --- STREAMING FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Streams new rewards to the contract
    /// @param newAmount The amount of asset tokens to stream
    /// @dev Starting a new stream will add the unvested portion of the previous stream to the new stream
    ///      and the new stream will be for `STREAMING_PERIOD`. See the comments in the contract description for more details.
    /// @custom:throws InvalidManager when the caller is not the manager of the vault
    function setRewardsStream(uint256 newAmount) external virtual onlyManager {
        Stream storage stream = currentStream;
        uint256 unvested;
        uint128 currentTimestamp = _timestamp();

        // If there is an active stream, calculate the unvested portion
        if (currentTimestamp < stream.end) {
            uint128 elapsed = currentTimestamp - stream.start;
            uint128 duration = stream.end - stream.start;
            unvested = stream.amount * (duration - elapsed) / duration;
        }

        // Update the stream to include both the potential unvested rollover and new rewards
        stream.amount = unvested + newAmount;
        stream.start = currentTimestamp;
        stream.end = currentTimestamp + STREAMING_PERIOD;

        // Pull the new rewards from the caller and immediately stake them
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), newAmount);
        _stake(newAmount);

        emit NewStreamRewards(msg.sender, stream.amount, stream.start, stream.end);
    }

    /// @notice Returns the current stream data
    /// @return amount The amount of asset tokens streamed over the streaming period
    /// @return remainingToken The amount of asset tokens staked remaining to be streamed
    /// @return start The start timestamp of the stream
    /// @return end The end timestamp of the stream
    /// @return remainingTime The remaining time in the stream (in seconds)
    function getCurrentStream()
        external
        view
        virtual
        returns (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime)
    {
        Stream storage stream = currentStream;
        amount = stream.amount;
        start = stream.start;
        end = stream.end;

        uint128 currentTimestamp = _timestamp();

        // If the stream is finished or not started, there is no remaining token or time
        if (currentTimestamp >= end || end <= start) {
            remainingToken = 0;
            remainingTime = 0;
        } else {
            remainingTime = end - currentTimestamp;
            remainingToken = amount * remainingTime / (end - start);
        }
    }

    /// @notice Set the new manager of the vault
    /// @param newManager The new manager of the vault
    function setManager(address newManager) external onlyOwner {
        _setManager(newManager);
    }

    function _setManager(address newManager) internal virtual {
        manager = newManager;
        emit ManagerChanged(newManager);
    }

    ////////////////////////////////////////////////////////////////
    /// --- MISSING FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Stake the deposit assets
    /// @dev This function is automatically called by `_deposit` during the deposit operation
    /// @param assets The amount of assets deposited
    function _stake(uint256 assets) internal virtual;

    /// @notice Unstake the assets the user is trying to withdraw
    /// @dev This function is automatically called by `_withdraw` during the withdrawal operation
    /// @param assets The amount of assets that will be withdrawn
    function _unstake(uint256 assets) internal virtual;

    /// @notice Get the current staked balance of this contract
    /// @dev This function is used by totalAssets to determine the usable balance of the vault
    /// @return The staked balance of this contract
    function _getStakedBalance() internal view virtual returns (uint256);

    /// @notice Claims the vault's rewards from the external source
    function claimStakingRewards() external virtual;

    ////////////////////////////////////////////////////////////////
    /// --- HELPERS FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Returns the current timestamp casted to a uint128
    /// @dev Considering the maximum timestamp is `2^128 - 1`, casting is safe here
    ///      no need of using the `SafeCast` library
    /// @return The current timestamp casted to a uint128
    function _timestamp() internal view returns (uint128) {
        return uint128(block.timestamp);
    }

    /// @notice Get the version of the contract
    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }
}
