// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import { PreLaunchBaseDepositor } from "src/common/depositor/PreLaunchBaseDepositor.sol";
import { ILiquidityGaugeV4 } from "src/common/interfaces/ILiquidityGaugeV4.sol";
import { ISdToken } from "src/common/interfaces/ISdToken.sol";

/// @title IPreLaunchLocker
/// @notice Interface for the PreLaunchLocker contract
interface IPreLaunchLocker {
    /// @notice The delay after which the locker can be force canceled by anyone
    function FORCE_CANCEL_DELAY() external view returns (uint256);

    /// @notice The immutable token to lock
    function token() external view returns (address);

    /// @notice The sdToken address
    function sdToken() external view returns (ISdToken);

    /// @notice The gauge address
    function gauge() external view returns (ILiquidityGaugeV4);

    /// @notice The current governance address
    function governance() external view returns (address);

    /// @notice The timestamp of the locker creation
    function timestamp() external view returns (uint96);

    /// @notice The depositor contract
    function depositor() external view returns (PreLaunchBaseDepositor);

    /// @notice Deposit tokens for a given receiver
    function deposit(uint256 amount, bool stake, address receiver) external;

    /// @notice Deposit tokens in this contract for the caller
    function deposit(uint256 amount, bool stake) external;

    /// @notice Set the depositor and lock the tokens in the given depositor contract
    function lock(address _depositor) external;

    /// @notice Withdraw the previously deposited tokens if the launch has been canceled
    function withdraw(uint256 amount, bool staked) external;

    /// @notice Set the state of the locker as CANCELED
    function cancelLocker() external;

    /// @notice Force cancel the locker
    function forceCancelLocker() external;

    /// @notice Transfer the governance to a new address
    function transferGovernance(address _governance) external;
}
