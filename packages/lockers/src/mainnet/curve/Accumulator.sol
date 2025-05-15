// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {CurveLocker, CurveProtocol} from "address-book/src/CurveEthereum.sol";
import {IFeeReceiver} from "common/interfaces/IFeeReceiver.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {DelegableAccumulator} from "src/common/accumulator/DelegableAccumulator.sol";
import {IFeeDistributor} from "src/common/interfaces/IFeeDistributor.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";

/// @author CurveAccumulator
/// @notice This contract is used to claim all the rewards the locker has received
///         from the different reward pools before sending them to Stake DAO's Liquidity Gauge (v4)
/// @dev This contract is the authorized distributor of the CRVUSD and CRV rewards in the gauge
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract CurveAccumulator is DelegableAccumulator, SafeModule {
    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge Address of the sdCRV-gauge contract
    /// @param _locker Address of the sdCRV locker
    /// @param _governance Address of the governance
    /// @param _gateway Address of the gateway
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    ///
    ///      Here are some hardcoded parameters automatically set by the contract:
    ///         - CRVUSD is the reward token
    ///         - CRV is the token
    ///         - VeCRV is the veToken
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _gauge, address _locker, address _governance, address _gateway)
        DelegableAccumulator(
            _gauge,
            CurveProtocol.CRV_USD, // rewardToken
            _locker,
            _governance,
            CurveProtocol.CRV, // token
            CurveProtocol.VECRV, // veToken
            CurveProtocol.VE_BOOST, // veBoost
            CurveProtocol.VE_BOOST_DELEGATION, // veBoostDelegation
            0 // multiplier
        )
        SafeModule(_gateway)
    {
        // @dev: Legacy lockers (before v4) used to claim fees from the strategy contract
        //       In v4, fees are claimed by calling the unique accountant contract.
        //       Here we initially set the already deployed strategy contract to smoothen the migration
        accountant = CurveLocker.STRATEGY;

        // Give full approval to the gauge for the CRV and CRV_USD tokens
        SafeTransferLib.safeApprove(CurveProtocol.CRV, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(CurveProtocol.CRV_USD, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Make the locker claim all the reward tokens before depositing them to the Liquidity Gauge (v4)
    function claimAndNotifyAll() external override {
        // 1. Claim locker's claimable CRVUSD rewards from Curve's fee distributor
        _execute_claim();

        // 2. Tell the locker to send the CRVUSD rewards to this contract if there are any
        uint256 claimedToken = ERC20(rewardToken).balanceOf(locker);
        if (claimedToken == 0) return;
        _execute_transfer(claimedToken);

        // 3. Tell the Strategy to send the accrued fees (CRV) to the fee receiver
        _claimAccumulatedFee();

        // 4. Notify the rewards to the Liquidity Gauge (V4)
        notifyReward(rewardToken);
        notifyReward(token);
    }

    function _notifyReward(address _tokenReward, uint256 _amount) internal override {
        // Charge the fee for the DAO, liquidity and claimer
        _chargeFee(_tokenReward, _amount);

        // Split fees for the specified token using the fee receiver contract
        if (feeReceiver != address(0)) IFeeReceiver(feeReceiver).split(_tokenReward);

        _amount = ERC20(_tokenReward).balanceOf(address(this));

        // Share the rewards with the delegation contract.
        if (_tokenReward == token) _amount -= _shareWithDelegation();
        if (_amount == 0) return;

        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);
    }

    ////////////////////////////////////////////////////////////////
    /// --- SAFE MODULE RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _execute_claim() internal virtual {
        _executeTransaction(CurveProtocol.FEE_DISTRIBUTOR, abi.encodeWithSelector(IFeeDistributor.claim.selector));
    }

    function _execute_transfer(uint256 amount) internal virtual {
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
        return type(CurveAccumulator).name;
    }
}
