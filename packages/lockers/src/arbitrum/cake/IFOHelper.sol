// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IFO} from "src/arbitrum/cake/IFO.sol";
import {ICakeIFOV8} from "src/common/interfaces/ICakeIFOV8.sol";
import {IExecutor} from "src/common/interfaces/IExecutor.sol";

/// @notice Small Helper to claim rewards from the IFO.
contract IFOHelper {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Address of the sdIFO contract
    IFO public immutable sdIFO;

    /// @notice Address of the pancake ifo contract
    ICakeIFOV8 public immutable cakeIFO;

    /// @notice Address of the executor contract
    IExecutor public immutable locker;

    /// @notice Address of the offering token
    ERC20 public immutable rewardToken;

    /// @notice Reward rate for each pool.
    mapping(uint8 => uint256) public rewardRate;

    /// @notice Reward claimed by each user for each pool.
    mapping(address => mapping(uint8 => uint256)) public rewardClaimed;

    /// @notice Emitted when a user claims rewards.
    event Claim(address indexed user, uint256 rewardToClaim);

    /// @notice Emitted when a call to an address fails.
    error CallFailed();

    /// @notice Emitted when a user has no deposit.
    error NoDeposit();

    /// @notice Emitted when the caller is not the locker.
    error Unauthorized();

    constructor(address _sdIFO, address _executor) {
        sdIFO = IFO(_sdIFO);
        cakeIFO = ICakeIFOV8(sdIFO.cakeIFO());
        rewardToken = sdIFO.oToken();
        locker = IExecutor(_executor);
    }

    /// @notice Release a vesting schedule.
    /// @param pid Pool id.
    /// @param vestingScheduleId Vesting schedule id.
    function release(uint8 pid, bytes32 vestingScheduleId) external {
        _release(pid, vestingScheduleId);
    }

    /// @notice Claim rewards.
    /// @param pid Pool id.
    /// @param vestingScheduleId Vesting schedule id.
    function claim(uint8 pid, bytes32 vestingScheduleId) external {
        uint256 deposited = sdIFO.depositors(msg.sender, pid);
        if (deposited == 0) revert NoDeposit();

        // release vesting rewards
        if (vestingScheduleId != bytes32(0)) {
            _release(pid, vestingScheduleId);
        }

        uint256 rewardToClaim = deposited.mulDiv(rewardRate[pid], 1e18) - rewardClaimed[msg.sender][pid];

        if (rewardToClaim != 0) {
            SafeTransferLib.safeTransfer(address(rewardToken), msg.sender, rewardToClaim);
            rewardClaimed[msg.sender][pid] += rewardToClaim;
        }

        emit Claim(msg.sender, rewardToClaim);
    }

    /// @notice Internal function to release a vesting schedule.
    /// @param pid Pool id.
    /// @param vestingScheduleId Vesting schedule id.
    function _release(uint8 pid, bytes32 vestingScheduleId) internal {
        uint256 snapshotOToken = rewardToken.balanceOf(address(locker));

        bytes memory releaseData = abi.encodeWithSignature("release(bytes32)", vestingScheduleId);
        (bool success,) = locker.execute(address(cakeIFO), 0, releaseData);
        if (!success) revert CallFailed();

        uint256 oTokenReleased = rewardToken.balanceOf(address(locker)) - snapshotOToken;

        if (oTokenReleased != 0) {
            // transfer token here
            bytes memory transferData =
                abi.encodeWithSignature("transfer(address,uint256)", address(this), oTokenReleased);
            (success,) = locker.execute(address(rewardToken), 0, transferData);
            if (!success) revert CallFailed();

            rewardRate[pid] += oTokenReleased.mulDiv(1e18, sdIFO.totalDeposits(pid));
        }
    }

    /// @notice Recover any ERC20 token sent to this contract.
    /// @param token Address of the token to recover.
    function recover(address token) external {
        if (msg.sender != address(locker)) revert Unauthorized();

        SafeTransferLib.safeTransfer(token, address(locker), ERC20(token).balanceOf(address(this)));
    }
}
