// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Autocompounded Stake DAO Vault
/// @notice This contract is a fully compliant ERC4626 streaming yield-bearing vault.
///         The rewards are streamed linearly over a fixed period and the vault is autocompounded.
/// @dev Streaming Reward Policy:
///      - If a new stream is started before the previous one ends, any unvested rewards from the previous stream
///        are automatically rolled over and added to the new stream amount. The combined total is then streamed
///        linearly over the new period.
///      - This mechanism results in a "premium" for users present at the time of the new stream, as the remaining
///        rewards from the previous stream will vest more quickly than originally scheduled.
///      - For optimal and fair reward distribution, it is strongly recommended to start a new stream only after
///        the previous stream has ended, or as close as possible to its scheduled end time. Starting new streams
///        prematurely can lead to accelerated vesting and may distort the intended reward schedule.
///      - This design is a trade-off for simplicity and to keep the reward calendar predictable and aligned.
/// @dev Direct Transfer Handling:
///      Any tokens sent directly to this contract (not via the setRewards function)
///      will be considered immediately vested and available to users. This means that accidental or
///      intentional direct transfers will increase the value returned by totalAssets() and can be
///      claimed by holders. This is an intentional design choice and should be considered
///      when integrating with or interacting with this vault.
/// @dev ERC4626 Virtual Shares/Assets Protection:
///      This contract inherits from OpenZeppelin's v5 ERC4626, which implements the "virtual shares/assets" protection mechanism.
///      This mechanism applies a +1 virtual offset to both totalSupply and totalAssets in the share/asset conversion formulas:
///         - shares = assets * (totalSupply() + 1) / (totalAssets() + 1)
///         - assets = shares * (totalAssets() + 1) / (totalSupply() + 1)
///      This contract uses a decimal offset set to 0, which is the OpenZeppelin default.
///      With this configuration, the protection ensures that donation/inflation attacks are unprofitable.
///      Even with a decimal offset of 0, the attacker's loss is at least equal to the user's deposit, as documented by OpenZeppelin.
contract AutocompoundedVault is ERC4626, Ownable2Step {
    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice The streaming period
    uint128 public immutable STREAMING_PERIOD;

    ////////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////

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

    /// @notice Initialize the asset and the shares token
    /// @param streamingPeriod The streaming period in seconds (e.g. 7 days)
    /// @param asset The asset token the users will deposit to the vault (e.g. sdYND)
    /// @param shareName The name of the shares token the users will receive
    /// @param shareSymbol The symbol of the shares token the users will receive
    /// @param owner The owner of the vault
    constructor(
        uint128 streamingPeriod,
        IERC20 asset,
        string memory shareName,
        string memory shareSymbol,
        address owner
    ) ERC4626(asset) ERC20(shareName, shareSymbol) Ownable(owner) {
        STREAMING_PERIOD = streamingPeriod;
    }

    ////////////////////////////////////////////////////////////////
    /// --- OVERRIDED PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Returns the total vested (usable) assets in the vault
    /// @dev This function returns the actual usable balance of the asset token that can be used for share calculations.
    ///      It subtracts unvested rewards from the vault's total balance:
    ///      - If there is no active stream, or if the current stream has ended (timestamp >= streamEnd),
    ///        returns the vault's full token balance
    ///      - If there is an active stream, subtracts the unvested portion of the stream from the vault's balance.
    ///        The unvested portion is calculated linearly based on the remaining time in the stream
    /// @return The total amount of vested asset token that are available for share calculations.
    ///         This is the value used by the ERC4626 implementation for deposit/withdrawal calculations
    function totalAssets() public view virtual override returns (uint256) {
        uint256 balance = IERC20(asset()).balanceOf(address(this));
        Stream storage stream = currentStream;
        uint128 currentTimestamp = _timestamp();

        // If there is no stream or the stream ended, return the real balance
        if (currentTimestamp >= stream.end) return balance;

        // If the stream is active, calculate the unvested portion and substract it from the balance
        uint128 remaining = stream.end - currentTimestamp;
        uint128 duration = stream.end - stream.start;
        uint256 futureRewards = stream.amount * remaining / duration;
        return balance - futureRewards;
    }

    ////////////////////////////////////////////////////////////////
    /// --- PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Streams new rewards to the contract
    /// @param newAmount The amount of asset tokens to stream
    /// @dev Starting a new stream will add the unvested portion of the previous stream to the new stream
    ///      and the new stream will be for `STREAMING_PERIOD`. See the comments in the contract description for more details.
    /// @custom:throws OwnableUnauthorizedAccount when the caller is not the owner
    function setRewards(uint256 newAmount) external virtual onlyOwner {
        Stream storage stream = currentStream;
        uint256 unvested;
        uint128 currentTimestamp = _timestamp();

        // If there is an active stream, calculate the unvested portion
        if (currentTimestamp < stream.end) {
            uint128 elapsed = currentTimestamp - stream.start;
            uint128 duration = stream.end - stream.start;
            unvested = stream.amount * (duration - elapsed) / duration;
        }

        // Add to the new stream the unvested portion of the previous stream
        stream.amount = unvested + newAmount;
        stream.start = currentTimestamp;
        stream.end = currentTimestamp + STREAMING_PERIOD;

        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), newAmount);
        emit NewStreamRewards(msg.sender, stream.amount, stream.start, stream.end);
    }

    /// @notice Returns the current stream data
    /// @return amount The amount of asset tokens streamed over the streaming period
    /// @return remainingToken The amount of asset tokens remaining to be streamed
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

    ////////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
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
