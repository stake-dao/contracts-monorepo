// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {AccumulatorBase} from "src/AccumulatorBase.sol";
import {IVeBoost} from "src/interfaces/IVeBoost.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title AccumulatorDelegableMultiToken
/// @notice This contract is an extension of the AccumulatorBase, designed to manage and distribute rewards
///         to a delegation contract. It leverages the veBoost mechanism to enhance reward distribution without
///         transferring governance rights.
///
///         This variant supports multiple reward tokens, allowing for flexible fee charging and delegation
///         across different token types. It applies a multiplier to the calculated delegation share, allowing
///         for flexible reward strategies.
///
///         Token Types:
///         - Reward Tokens: Tokens that can be charged fees (DAO, liquidity, claimer fees). These tokens
///           generate fee revenue for the protocol and are distributed to users through the Liquidity Gauge.
///         - Delegatable Token: The single token that gets shared with the veBoost delegation contract based on boost
///           calculations. A portion is sent to delegation, the remainder goes to the Liquidity Gauge.
///           This token can also be a reward token (e.g., BAL in Balancer).
abstract contract AccumulatorDelegableMultiToken is AccumulatorBase {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    address public immutable VE_TOKEN;
    address public immutable DELEGATABLE_TOKEN;

    ///////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////
    address public veBoost;
    address public veBoostDelegation;
    uint256 public multiplier;

    /// @notice Array of tokens that are considered reward tokens (can be charged fees)
    address[] public rewardTokens;

    ///////////////////////////////////////////////////////////////
    /// --- EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when the multiplier is set
    event MultiplierSet(uint256 oldMultiplier, uint256 newMultiplier);

    /// @notice Emitted when the veBoost is set
    event VeBoostSet(address oldVeBoost, address newVeBoost);

    /// @notice Emitted when the veBoostDelegation is set
    event VeBoostDelegationSet(address oldVeBoostDelegation, address newVeBoostDelegation);

    /// @notice Emitted when a token is registered as a reward token
    event RewardTokenRegistered(address indexed token);

    /// @notice Emitted when a token is unregistered as a reward token
    event RewardTokenUnregistered(address indexed token);

    /// @notice Emitted when the rewards are shared with the delegation contract
    event RewardsSharedWithDelegation(address indexed token, address indexed to, uint256 amount);

    ///////////////////////////////////////////////////////////////
    /// --- ERRORS
    ///////////////////////////////////////////////////////////////

    error RewardTokenNotRegistered();

    /// @notice Constructor for the AccumulatorDelegableMultiToken contract.
    /// @param _gauge The address of the gauge.
    /// @param _rewardToken The address of the primary reward token (for backward compatibility).
    /// @param _locker The address of the locker.
    /// @param _governance The address of the governance.
    /// @param _token The address of the primary delegation token (e.g., BAL, CRV).
    /// @param _veToken The address of the VE_TOKEN (e.g., veCRV) used to calculate the boost.
    /// @param _veBoost The address of the veBoost contract, which manages the boost received.
    /// @param _veBoostDelegation The address of the delegation contract to which rewards are distributed.
    /// @param _multiplier A scaling factor applied to the calculated delegation share.
    constructor(
        address _gauge,
        address _rewardToken,
        address _locker,
        address _governance,
        address _token,
        address _veToken,
        address _veBoost,
        address _veBoostDelegation,
        uint256 _multiplier
    ) AccumulatorBase(_gauge, _rewardToken, _locker, _governance) {
        require(_token != address(0), ZERO_ADDRESS());
        require(_veToken != address(0), ZERO_ADDRESS());
        require(_veBoost != address(0), ZERO_ADDRESS());
        require(_veBoostDelegation != address(0), ZERO_ADDRESS());

        VE_TOKEN = _veToken;
        DELEGATABLE_TOKEN = _token;
        veBoost = _veBoost;
        veBoostDelegation = _veBoostDelegation;
        multiplier = _multiplier;

        // Register the primary reward token by default
        _setRewardToken(_rewardToken);
    }

    ///////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Shares the rewards with the delegation contract for a specific token
    /// @param _token The token to share with delegation
    /// @return delegationShare The amount shared with delegation
    function _shareWithDelegation(address _token) internal returns (uint256 delegationShare) {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (amount == 0) return 0;
        if (veBoost == address(0) || veBoostDelegation == address(0)) return 0;

        /// Share the rewards with the delegation contract.
        uint256 boostReceived = IVeBoost(veBoost).received_balance(locker);
        if (boostReceived == 0) return 0;

        /// Get the veToken balance of the locker.
        uint256 lockerVEToken = IERC20(VE_TOKEN).balanceOf(locker);

        /// Calculate the percentage of token delegated to the VeBoost contract.
        uint256 bpsDelegated = boostReceived * DENOMINATOR / lockerVEToken;

        /// Calculate the expected delegation share.
        delegationShare = amount * bpsDelegated / DENOMINATOR;

        /// Apply the multiplier.
        if (multiplier != 0) delegationShare = delegationShare * multiplier / DENOMINATOR;

        SafeTransferLib.safeTransfer(_token, veBoostDelegation, delegationShare);
        emit RewardsSharedWithDelegation(_token, veBoostDelegation, delegationShare);
    }

    ///////////////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Override _chargeFee to support multiple reward tokens
    /// @param _token token to charge fee for
    /// @param _amount amount to charge fee for
    function _chargeFee(address _token, uint256 _amount) internal virtual override returns (uint256 _charged) {
        if (_amount == 0) return 0;

        // Send the fees to all the stored fee receivers based on their fee weight
        Split[] memory _feeSplit = getFeeSplit();

        uint256 _length = _feeSplit.length;
        uint256 fee;
        for (uint256 i; i < _length;) {
            fee = (_amount * _feeSplit[i].fee) / DENOMINATOR;
            SafeTransferLib.safeTransfer(_token, _feeSplit[i].receiver, fee);
            emit FeeTransferred(_feeSplit[i].receiver, fee, false);

            _charged += fee;

            unchecked {
                ++i;
            }
        }

        // If claimer fee is set, send the claimer fee to the caller
        uint256 _claimerFee = claimerFee;
        if (_claimerFee > 0) {
            fee = (_amount * _claimerFee) / DENOMINATOR;
            _charged += fee;

            SafeTransferLib.safeTransfer(_token, msg.sender, fee);
            emit FeeTransferred(msg.sender, fee, true);
        }
    }

    ///////////////////////////////////////////////////////////////
    /// --- UTILS FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Checks if a token is a reward token
    /// @param _token The token address to check
    /// @return bool True if the token is a reward token, false otherwise
    function _isRewardToken(address _token) internal view returns (bool) {
        uint256 _length = rewardTokens.length;
        for (uint256 i; i < _length; i++) {
            if (rewardTokens[i] == _token) return true;
        }
        return false;
    }

    /// @notice Checks if a token is delegatable
    /// @param _token The token address to check
    /// @return bool True if the token is delegatable, false otherwise
    function _isDelegatableToken(address _token) internal view returns (bool) {
        return _token == DELEGATABLE_TOKEN;
    }

    /// @notice Utility function to remove an element from an array
    /// @param _array The array to remove from
    /// @param _element The element to remove
    function _removeFromArray(address[] storage _array, address _element) internal {
        uint256 _length = _array.length;
        for (uint256 i; i < _length; i++) {
            if (_array[i] == _element) {
                // If necessary, replace with last element and pop
                if (i < _length - 1) _array[i] = _array[_length - 1];
                _array.pop();
                break;
            }
        }
    }

    ///////////////////////////////////////////////////////////////
    /// --- GOVERNANCE FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Register or unregister a token as a reward token
    /// @param _token The token address
    function setRewardToken(address _token) external onlyGovernance {
        require(_token != address(0), ZERO_ADDRESS());
        _setRewardToken(_token);
    }

    /// @notice Internal function to set a token as reward
    /// @dev    Only adds if not already present.
    function _setRewardToken(address _token) internal {
        if (_isRewardToken(_token)) return;

        rewardTokens.push(_token);
        emit RewardTokenRegistered(_token);

        SafeTransferLib.safeApprove(_token, gauge, type(uint256).max);
        emit RewardTokenApproved(_token); // legacy-compatibility
    }

    /// @notice Remove a token from the reward tokens array
    /// @param _token The token address
    function removeRewardToken(address _token) external onlyGovernance {
        require(_isRewardToken(_token), RewardTokenNotRegistered());

        SafeTransferLib.safeApprove(_token, gauge, 0);
        _removeFromArray(rewardTokens, _token);

        emit RewardTokenUnregistered(_token);
    }

    /// @notice Sets the multiplier
    /// @param _multiplier The new multiplier
    function setMultiplier(uint256 _multiplier) external onlyGovernance {
        emit MultiplierSet(multiplier, _multiplier);
        multiplier = _multiplier;
    }

    /// @notice Sets the veBoost
    /// @param _veBoost The new veBoost
    function setVeBoost(address _veBoost) external onlyGovernance {
        emit VeBoostSet(veBoost, _veBoost);
        veBoost = _veBoost;
    }

    /// @notice Sets the veBoostDelegation
    /// @param _veBoostDelegation The new veBoostDelegation
    function setVeBoostDelegation(address _veBoostDelegation) external onlyGovernance {
        emit VeBoostDelegationSet(veBoostDelegation, _veBoostDelegation);
        veBoostDelegation = _veBoostDelegation;
    }
}
