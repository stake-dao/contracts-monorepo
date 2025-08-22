// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeModule} from "src/utils/SafeModule.sol";
import {ISafe} from "src/interfaces/ISafe.sol";
import {ILiquidityGaugeV4} from "src/interfaces/ILiquidityGaugeV4.sol";
import {IAccumulator} from "src/interfaces/IAccumulator.sol";

/// @title AccumulatorMigrationSafeModule
/// @notice Gnosis Safe module that migrate from one accumulator to another in a
///         single transaction while keeping gauges and related components in sync.
/// @dev    The module:
///         1. Disables the `oldAccumulator` Safe module and enables the
///            `newAccumulator`.
///         2. Re-wires the gauge reward distributors
///         3. Propagates the new accumulator address to arbitrary contracts
///            passed in through the `components` array by calling
///            `setAccumulator(address)` on them. This is useful to migrate
///            a strategy, a depositor, etc.
contract AccumulatorMigrationSafeModule is SafeModule, Ownable2Step, ReentrancyGuard {
    ///////////////////////////////////////////////////////////////
    /// --- IMMUTABLES
    ///////////////////////////////////////////////////////////////

    address public immutable LOCKER;

    ///////////////////////////////////////////////////////////////
    /// --- ERRORS / EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Throws if the old accumulator is not enabled or incorrect
    error InvalidOldAccumulator();

    /// @notice Throws if the new accumulator is address 0 or incorrect
    error InvalidNewAccumulator();

    /// @notice Throws if the different stored lockers do not match
    error IncorrectLocker();

    /// @notice Throws if the gauge admin is not the gateway
    error InvalidGaugeAdmin();

    /// @notice Throws if the locker is address 0
    error InvalidLocker();

    /// @notice Emitted after a successful accumulator migration.
    /// @param oldAccumulator The accumulator that has been disabled.
    /// @param newAccumulator The accumulator that has been enabled.
    event AccumulatorMigrated(address indexed oldAccumulator, address indexed newAccumulator);

    /// @notice Deploys the migration module.
    /// @param _locker   Address of the Stake DAO locker to acts on.
    /// @param _gateway  Gateway address used by the underlying `SafeModule`
    ///                  abstraction for module executions.
    /// @dev   `_locker` may or may not be a Safe module. If it is, both the
    ///        `_locker` and the `gateway` will be the same address. If it isn't,
    ///        the `gateway` will be the address of the Safe module that is
    ///        responsible for interacting with the `_locker`.
    /// @custom:throws InvalidLocker if the `_locker` is address 0.
    /// @custom:throws InvalidGateway if the `_gateway` is address 0.
    constructor(address _locker, address _gateway) SafeModule(_gateway) Ownable(msg.sender) {
        require(_locker != address(0), InvalidLocker());
        LOCKER = _locker;
    }

    ////////////////////////////////////////////////////////////////
    /// --- EXTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Executes the accumulator migration.
    /// @dev    Requirements:
    ///         - `oldAccumulator` must be an enabled Safe module and different
    ///           from this migration contract.
    ///         - `newAccumulator` cannot be the zero address nor this contract.
    ///         - Both accumulators safe modules must target the same `LOCKER` address.
    ///         - The locker must be the admin of the gauge linked to the new
    ///           accumulator. This is required to set the new accumulator as the reward distributor.
    ///         On success the function:
    ///         1. Swaps the Safe modules.
    ///         2. Updates reward distributors in the gauge.
    ///         3. Calls `setAccumulator(newAccumulator)` on every contract in `components`.
    /// @param oldAccumulator Address of the accumulator to disable.
    /// @param newAccumulator Address of the accumulator to enable.
    /// @param components Array of extra contracts that need their
    ///                   accumulator reference updated. This is useful in some
    ///                   cases to set the new accumulator in specific non-generic contracts
    ///                   like the depositor of Spectra or the Frax Locker.
    function migrate(address oldAccumulator, address newAccumulator, address[] calldata components)
        external
        onlyOwner
        nonReentrant
    {
        require(oldAccumulator != address(this), InvalidOldAccumulator());
        require(ISafe(GATEWAY).isModuleEnabled(oldAccumulator), InvalidOldAccumulator());
        require(newAccumulator != address(0) && newAccumulator != address(this), InvalidNewAccumulator());
        require(IAccumulator(oldAccumulator).locker() == LOCKER, IncorrectLocker());
        require(IAccumulator(newAccumulator).locker() == LOCKER, IncorrectLocker());

        // Ensure the locker is the admin of the gauge
        ILiquidityGaugeV4 gauge = ILiquidityGaugeV4(IAccumulator(newAccumulator).gauge());
        require(gauge.admin() == LOCKER, InvalidGaugeAdmin());

        // Replace the old safe-module accumulator with the new one
        _executeTransaction(GATEWAY, abi.encodeWithSelector(ISafe.disableModule.selector, oldAccumulator));
        _executeTransaction(GATEWAY, abi.encodeWithSelector(ISafe.enableModule.selector, newAccumulator));

        // Set the new accumulator as the reward distributor in the gauge
        address rewardToken = IAccumulator(newAccumulator).rewardToken();
        gauge.set_reward_distributor(rewardToken, newAccumulator);

        // Set the new accumulator in the extra relevant components
        // The locker must be authorized to call the components
        for (uint256 i; i < components.length; i++) {
            if (components[i] != address(0)) {
                _executeTransaction(components[i], abi.encodeWithSignature("setAccumulator(address)", newAccumulator));
            }
        }

        emit AccumulatorMigrated(oldAccumulator, newAccumulator);
    }

    ////////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Returns the address of the locker.
    function _getLocker() internal view override returns (address) {
        return LOCKER;
    }

    ////////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Returns the semantic version of the contract.
    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }
}
