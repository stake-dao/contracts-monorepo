// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FraxProtocol} from "address-book/src/FraxFraxtal.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {BaseDepositor} from "src/common/depositor/BaseDepositor.sol";
import {ISdTokenOperator} from "src/common/interfaces/ISdTokenOperator.sol";
import {IVestedFXS} from "src/common/interfaces/IVestedFXS.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";
import {FXTLDelegation} from "src/fraxtal/FXTLDelegation.sol";

/// @title BaseDepositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract FraxDepositor is BaseDepositor, FXTLDelegation, SafeModule {
    using SafeCast for uint256;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    address public constant VE_TOKEN = FraxProtocol.VEFXS;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _token Address of the token
    /// @param _minter Address of the minter (on fraxtal it is the main operator)
    /// @param _gauge Address of the sdToken gauge
    /// @param _mainOperator Address of the main operator (the minter)
    /// @param _delegationRegistry Address of the fraxtal delegation registry
    /// @param _initialDelegate Address of the delegate that receives network reward
    /// @param _gateway Address of the gateway contract. Can be the same as the locker.
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    ///
    ///      Here are some hardcoded parameters automatically set by the contract:
    ///         - FXS is the reward token
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    /// @custom:throws FXTLDelegationFailed if the delegation fails
    constructor(
        address _token,
        address _locker,
        address _minter,
        address _gauge,
        address _mainOperator,
        address _delegationRegistry,
        address _initialDelegate,
        address _gateway
    )
        BaseDepositor(_token, _locker, _minter, _gauge, 4 * 365 days)
        FXTLDelegation(_delegationRegistry, _initialDelegate)
        SafeModule(_gateway)
    {
        // set the minter as main operator
        minter = _mainOperator;
    }

    ///////////////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// Override the createLock function to prevent reverting.
    function createLock(uint256 _amount) external override {}

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    /// custom:throws if `unlockTime` > type(uint128).max
    function _lockToken(uint256 _value) internal override {
        if (_value != 0) _execute_increaseAmount(_value);

        // Calculate the theoretical new unlock time
        uint256 _unlockTime = block.timestamp + MAX_LOCK_DURATION;

        // Check if the new unlock time is greater than the current locked balance's end time
        bool _canIncrease = _unlockTime > (IVestedFXS(VE_TOKEN).lockedEnd(locker, 0));
        if (_canIncrease) _execute_increaseUnlockTime(_unlockTime.toUint128());
    }

    /// @notice Increase the lock amount
    /// @param amount The amount of FXS to lock
    /// @dev The second parameter represents the index of the user's lock that getting the increased amount. Hardcoded to 0.
    function _execute_increaseAmount(uint256 amount) internal virtual {
        _executeTransaction(VE_TOKEN, abi.encodeWithSelector(IVestedFXS.increaseAmount.selector, amount, 0));
    }

    /// @notice Increase the unlock time
    /// @param unlockTime The new unlock time
    /// @dev The second parameter represents the index of the user's lock that getting the increased amount. Hardcoded to 0.
    function _execute_increaseUnlockTime(uint128 unlockTime) internal virtual {
        _executeTransaction(VE_TOKEN, abi.encodeWithSelector(IVestedFXS.increaseUnlockTime.selector, unlockTime, 0));
    }

    ///////////////////////////////////////////////////////////////
    /// --- SETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Set the gauge to deposit sdToken
    /// @param _gauge gauge address
    function setGauge(address _gauge) external override onlyGovernance {
        gauge = _gauge;
        if (_gauge != address(0)) {
            address _token = ISdTokenOperator(minter).sdToken();
            /// Approve sdToken to locker.
            SafeTransferLib.safeApprove(_token, _gauge, type(uint256).max);
        }
    }

    /// @notice Set the operator for sdToken (leave it empty because on fraxtal the depositor is not the sdToken's operator)
    function setSdTokenMinterOperator(address) external override onlyGovernance {}

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    function _getLocker() internal view override returns (address) {
        return locker;
    }

    function version() external pure virtual override returns (string memory) {
        return "4.0.0";
    }

    function name() external view virtual override returns (string memory) {
        return type(FraxDepositor).name;
    }
}
