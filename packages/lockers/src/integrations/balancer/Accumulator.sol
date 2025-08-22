// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {BalancerLocker, BalancerProtocol} from "@address-book/src/BalancerEthereum.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";
import {IFeeReceiver} from "@common/interfaces/IFeeReceiver.sol";
import {AccumulatorDelegableMultiToken} from "src/AccumulatorDelegableMultiToken.sol";
import {BalancerFeeDistributor} from "src/interfaces/BalancerFeeDistributor.sol";
import {SafeModule} from "src/utils/SafeModule.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BalancerAccumulator
/// @notice This contract is used to claim all the rewards the locker has received
///         from the different reward pools before sending them to Stake DAO's Liquidity Gauge (v4)
/// @dev Supports multi-token rewards with both USDC and BAL being claimable and fee-bearing
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract BalancerAccumulator is AccumulatorDelegableMultiToken, SafeModule {
    /// @notice Fee distributor address.
    address public constant FEE_DISTRIBUTOR = BalancerProtocol.FEE_DISTRIBUTOR;

    error CLAIMED_LENGTH_MISMATCH();

    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge Address of the sdBAL-gauge contract
    /// @param _locker Address of the sdBAL locker
    /// @param _governance Address of the governance
    /// @param _gateway Address of the gateway
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    ///
    ///      Here are some hardcoded parameters automatically set by the contract:
    ///         - USDC is the primary reward token
    ///         - BAL is also a reward token (multi-token support)
    ///         - VeBAL is the veToken
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _gauge, address _locker, address _governance, address _gateway)
        AccumulatorDelegableMultiToken(
            _gauge,
            Common.USDC, // primary rewardToken
            _locker,
            _governance,
            BalancerProtocol.BAL, // primary delegation token
            BalancerProtocol.VEBAL, // veToken
            BalancerProtocol.VE_BOOST, // veBoost
            BalancerLocker.VE_BOOST_DELEGATION, // veBoostDelegation
            0 // multiplier
        )
        SafeModule(_gateway)
    {
        // @dev: Legacy lockers (before v4) used to claim fees from the strategy contract
        //       In v4, fees are claimed by calling the unique accountant contract.
        //       Here we initially set the already deployed strategy contract to smoothen the migration
        accountant = BalancerLocker.STRATEGY;

        // Balancer-specific: BAL is both a reward token AND a delegatable token
        // This is different from other protocols (e.g., Curve) where the delegation token (CRV)
        // is only delegatable but not a reward token. In Balancer, both USDC and BAL generate
        // fee revenue and are distributed to users through the Liquidity Gauge.
        _setRewardToken(BalancerProtocol.BAL);
    }

    ///////////////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Make the locker claim all the reward tokens before depositing them to the Liquidity Gauge (v4)
    ///         Charge the fees only on the part of the reward tokens that are not delegatable
    /// @dev This function assumes the `claimed` array returned by the fees distributor
    //       is in the exact same order as the `rewardTokens` array passed as argument.
    //       At the time of writing, this is the case for Balancer.
    function claimAndNotifyAll() external override {
        // Claim all registered reward tokens from the fee distributor
        uint256[] memory claimed = _execute_claimMultipleRewards();
        uint256 length = rewardTokens.length;
        require(length == claimed.length, CLAIMED_LENGTH_MISMATCH());
        for (uint256 i; i < length; i++) {
            if (claimed[i] > 0) _execute_transfer(rewardTokens[i], claimed[i]);
        }

        // Tell the Strategy to send the accrued fees to the fee receiver
        _claimAccumulatedFee();

        // Notify all registered reward tokens to the Liquidity Gauge (V4)
        _notifyAllRewardTokens(claimed);
    }

    /// @notice Notify all registered reward tokens to the gauge
    function _notifyAllRewardTokens(uint256[] memory claimed) internal {
        // Notify all reward tokens after charging the fees for the DAO, liquidity and claimer
        uint256 length = claimed.length;
        for (uint256 i; i < length; i++) {
            _chargeFee(rewardTokens[i], claimed[i]);
            _notifyReward(rewardTokens[i], claimed[i]);
        }

        // Notify the delegatable token (all the remaining tokens)
        notifyReward(DELEGATABLE_TOKEN);
    }

    /// @notice Override _notifyReward to support delegation for any token
    /// @param _tokenReward token to notify
    /// @param _amount amount to notify
    function _notifyReward(address _tokenReward, uint256 _amount) internal virtual override {
        // Split fees for the specified token using the fee receiver contract
        if (feeReceiver != address(0)) IFeeReceiver(feeReceiver).split(_tokenReward);

        // Get the balance of the token in the accumulator and return if 0
        _amount = IERC20(_tokenReward).balanceOf(address(this));
        if (_amount == 0) return;

        // Share the rewards with the delegation contract if the token is delegatable
        if (_isDelegatableToken(_tokenReward)) _amount -= _shareWithDelegation(_tokenReward);
        if (_amount == 0) return;

        // Deposit the token to the gauge
        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);
    }

    ////////////////////////////////////////////////////////////////
    /// --- SAFE MODULE RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Claims all registered reward tokens from the fee distributor
    function _execute_claimMultipleRewards() internal returns (uint256[] memory claimed) {
        uint256 length = rewardTokens.length;
        if (length == 0) return claimed;

        // Claim all registered tokens at once using the multi-token claim function
        bytes memory returnData = _executeTransaction(
            FEE_DISTRIBUTOR, abi.encodeWithSelector(BalancerFeeDistributor.claimTokens.selector, locker, rewardTokens)
        );
        claimed = abi.decode(returnData, (uint256[]));
    }

    /// @notice Transfer a specific token from locker to accumulator
    /// @param _token The token to transfer
    /// @param _amount The amount to transfer
    function _execute_transfer(address _token, uint256 _amount) internal {
        _executeTransaction(_token, abi.encodeWithSelector(IERC20.transfer.selector, address(this), _amount));
    }

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    function _getLocker() internal view override returns (address) {
        return locker;
    }

    function version() external pure virtual override returns (string memory) {
        return "4.1.0";
    }

    function name() external view virtual override returns (string memory) {
        return type(BalancerAccumulator).name;
    }
}
