// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IAccumulator {
    /// @notice Split definition used for fee distribution
    struct Split {
        address receiver;
        uint96 fee; // 1e18-precision BPS
    }

    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES (accessors)
    ///////////////////////////////////////////////////////////////

    function DENOMINATOR() external view returns (uint256);

    function gauge() external view returns (address);
    function rewardToken() external view returns (address);
    function locker() external view returns (address);

    ///////////////////////////////////////////////////////////////
    /// --- STATE (public variable accessors)
    ///////////////////////////////////////////////////////////////

    function claimerFee() external view returns (uint256);
    function accountant() external view returns (address);
    function governance() external view returns (address);
    function futureGovernance() external view returns (address);
    function feeReceiver() external view returns (address);

    ///////////////////////////////////////////////////////////////
    /// --- CORE EXTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// Claim all rewards for the locker and notify the gauge.
    function claimAndNotifyAll() external;

    /// Notify the full balance of a given `token` to the gauge.
    function notifyReward(address token) external;

    /// Return the current fee-split table.
    function getFeeSplit() external view returns (Split[] memory);

    ///////////////////////////////////////////////////////////////
    /// --- GOVERNANCE FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function setClaimerFee(uint256 _claimerFee) external;
    function setFeeReceiver(address _feeReceiver) external;
    function transferGovernance(address _futureGovernance) external;
    function acceptGovernance() external;
    function approveNewTokenReward(address _newTokenReward) external;
    function setFeeSplit(Split[] calldata splits) external;
    function setAccountant(address _accountant) external;

    /// Emergency token rescue
    function rescueERC20(address _token, uint256 _amount, address _recipient) external;

    ///////////////////////////////////////////////////////////////
    /// --- METADATA
    ///////////////////////////////////////////////////////////////

    function name() external view returns (string memory);
    function version() external pure returns (string memory);

    ///////////////////////////////////////////////////////////////
    /// --- EVENTS
    ///////////////////////////////////////////////////////////////

    event FeeSplitUpdated(Split[] newFeeSplit);
    event RewardTokenApproved(address newRewardToken);
    event ClaimerFeeUpdated(uint256 newClaimerFee);
    event FeeReceiverUpdated(address newFeeReceiver);
    event AccountantUpdated(address newAccountant);
    event GovernanceUpdateProposed(address newFutureGovernance);
    event GovernanceUpdateAccepted(address newGovernance);
    event FeeTransferred(address indexed receiver, uint256 amount, bool indexed isClaimerFee);
}
