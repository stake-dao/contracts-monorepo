// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CommonAddresses} from "address-book/src/common.sol";
import {BAL as BalancerProtocol} from "address-book/src/lockers/1.sol";
import {Balancer} from "address-book/src/protocols/1.sol";
import {IFeeReceiver} from "common/interfaces/IFeeReceiver.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {DelegableAccumulator} from "src/common/accumulator/DelegableAccumulator.sol";
import {BalancerFeeDistributor} from "src/common/interfaces/BalancerFeeDistributor.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";

/// @title BalancerAccumulator
/// @notice This contract is used to claim all the rewards the locker has received
///         from the different reward pools before sending them to Stake DAO's Liquidity Gauge (v4)
/// @dev This contract is the authorized distributor of the BAL and USDC rewards in the gauge
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract BalancerAccumulator is DelegableAccumulator, SafeModule {
    /// @notice Fee distributor address.
    address public constant FEE_DISTRIBUTOR = Balancer.FEE_DISTRIBUTOR;

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
    ///         - USDC is the reward token
    ///         - BAL is the token
    ///         - VeBAL is the veToken
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _gauge, address _locker, address _governance, address _gateway)
        DelegableAccumulator(
            _gauge,
            CommonAddresses.USDC, // rewardToken
            _locker,
            _governance,
            Balancer.BAL, // token
            Balancer.VEBAL, // veToken
            Balancer.VE_BOOST, // veBoost
            Balancer.VE_BOOST_DELEGATION, // veBoostDelegation
            0 // multiplier
        )
        SafeModule(_gateway)
    {
        // @dev: Legacy lockers (before v4) used to claim fees from the strategy contract
        //       In v4, fees are claimed by calling the unique accountant contract.
        //       Here we initially set the already deployed strategy contract to smoothen the migration
        accountant = BalancerProtocol.STRATEGY;

        // Give full approval to the gauge for the BAL and USDC tokens
        SafeTransferLib.safeApprove(Balancer.BAL, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(CommonAddresses.USDC, _gauge, type(uint256).max);
    }

    ///////////////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Make the locker claim all the reward tokens before depositing them to the Liquidity Gauge (v4)
    function claimAndNotifyAll() external override {
        // Claim locker's claimable USDC rewards and transfer them here
        uint256 claimed = _execute_claimRewards();
        _execute_transfer(claimed);

        // Tell the Strategy to send the accrued fees to the fee receiver
        _claimAccumulatedFee();

        // Notify the rewards to the Liquidity Gauge (V4)
        notifyReward({token: rewardToken, claimFeeStrategy: false});
        notifyReward({token: token, claimFeeStrategy: true});
    }

    function _notifyReward(address _tokenReward, uint256 _amount, bool _pullFromFeeReceiver) internal override {
        _chargeFee(_tokenReward, _amount);

        // Split fees for the specified token using the fee receiver contract
        // Function not permissionless, to prevent sending to that accumulator and re-splitting (_chargeFee)
        if (_pullFromFeeReceiver && feeReceiver != address(0)) {
            IFeeReceiver(feeReceiver).split(_tokenReward);
        }

        _amount = ERC20(_tokenReward).balanceOf(address(this));

        // Share the BAL rewards with the delegation contract.
        if (_tokenReward == token) _amount -= _shareWithDelegation();
        if (_amount == 0) return;

        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);
    }

    ////////////////////////////////////////////////////////////////
    /// --- SAFE MODULE RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _execute_claimRewards() internal returns (uint256 claimed) {
        bytes memory returnData = _executeTransaction(
            FEE_DISTRIBUTOR, abi.encodeWithSelector(BalancerFeeDistributor.claimToken.selector, locker, rewardToken)
        );
        claimed = abi.decode(returnData, (uint256));
    }

    function _execute_transfer(uint256 amount) internal {
        _executeTransaction(rewardToken, abi.encodeWithSelector(ERC20.transfer.selector, address(this), amount));
    }

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
        return type(BalancerAccumulator).name;
    }
}
