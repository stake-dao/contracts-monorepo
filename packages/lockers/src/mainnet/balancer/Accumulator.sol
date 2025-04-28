// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";
import {IVeBoost} from "src/common/interfaces/IVeBoost.sol";
import {IVeBoostDelegation} from "src/common/interfaces/IVeBoostDelegation.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IFeeReceiver} from "common/interfaces/IFeeReceiver.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {Balancer} from "address-book/src/protocols/1.sol";
import {BalancerFeeDistributor} from "src/common/interfaces/BalancerFeeDistributor.sol";
import {BAL as BalancerProtocol} from "address-book/src/lockers/1.sol";

/// @notice BAL BaseAccumulator
/// @author StakeDAO
contract BalancerAccumulator is BaseAccumulator, SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice BAL token address.
    address public constant BAL = Balancer.BAL;

    /// @notice USDC token address.
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice VeBAL token address.
    address public constant VE_BAL = Balancer.VEBAL;

    /// @notice Fee distributor address.
    address public constant FEE_DISTRIBUTOR = 0xD3cf852898b21fc233251427c2DC93d3d604F3BB;

    ///////////////////////////////////////////////////////////////
    /// --- STATES
    ///////////////////////////////////////////////////////////////

    /// @notice Ve Boost V2
    IVeBoost public veBoost = IVeBoost(0x67F8DF125B796B05895a6dc8Ecf944b9556ecb0B);

    /// @notice Ve Boost FXTLDelegation.
    IVeBoostDelegation public veBoostDelegation = IVeBoostDelegation(0xda9846665Bdb44b0d0CAFFd0d1D4A539932BeBdf);

    /// @notice Multiplier applied to the delegation share of BAL rewards sent to veBoost delegators.
    /// @dev Scales the calculated delegation share. Set as a fixed-point value with 1e18 = 100%.
    uint256 public multiplier;

    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    constructor(address _gauge, address _locker, address _governance, address _gateway)
        BaseAccumulator(_gauge, USDC, _locker, _governance)
        SafeModule(_gateway)
    {
        strategy = BalancerProtocol.STRATEGY;
        // Give full approval to the gauge for the BAL and USDC tokens
        SafeTransferLib.safeApprove(BAL, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(USDC, _gauge, type(uint256).max);
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
        _claimFeeStrategy();

        // Notify the rewards to the Liquidity Gauge (V4)
        notifyReward(USDC, false, false);
        notifyReward(BAL, true, true);
    }

    function _notifyReward(address _tokenReward, uint256 _amount, bool _pullFromFeeReceiver) internal override {
        _chargeFee(_tokenReward, _amount);

        if (_pullFromFeeReceiver && feeReceiver != address(0)) {
            // Split fees for the specified token using the fee receiver contract
            // Function not permissionless, to prevent sending to that accumulator and re-splitting (_chargeFee)
            IFeeReceiver(feeReceiver).split(_tokenReward);
        }

        _amount = ERC20(_tokenReward).balanceOf(address(this));

        if (_tokenReward == BAL) {
            /// Share the BAL rewards with the delegation contract.
            _amount -= _shareWithDelegation();
        }

        if (_amount == 0) return;
        ILiquidityGauge(gauge).deposit_reward_token(_tokenReward, _amount);
    }

    /// @notice Share the BAL Rewards from Strategy
    function _shareWithDelegation() internal returns (uint256 delegationShare) {
        uint256 amount = ERC20(BAL).balanceOf(address(this));
        if (amount == 0) return 0;
        if (address(veBoost) == address(0) || address(veBoostDelegation) == address(0)) return 0;

        /// Share the BAL rewards with the delegation contract.
        uint256 boostReceived = veBoost.received_balance(locker);
        if (boostReceived == 0) return 0;

        /// Get the VeBAL balance of the locker.
        uint256 lockerVeBal = ERC20(VE_BAL).balanceOf(locker);

        /// Calculate the percentage of BAL delegated to the VeBoost contract.
        uint256 bpsDelegated = (boostReceived * DENOMINATOR / lockerVeBal);

        /// Calculate the expected delegation share.
        delegationShare = amount * bpsDelegated / DENOMINATOR;

        /// Apply the multiplier.
        if (multiplier != 0) {
            delegationShare = delegationShare * multiplier / DENOMINATOR;
        }

        SafeTransferLib.safeTransfer(BAL, address(veBoostDelegation), delegationShare);
    }

    ////////////////////////////////////////////////////////////////
    /// --- SAFE MODULE RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _execute_claimRewards() internal returns (uint256 claimed) {
        bytes memory returnData = _executeTransaction(
            FEE_DISTRIBUTOR, abi.encodeWithSelector(BalancerFeeDistributor.claimToken.selector, locker, USDC)
        );
        claimed = abi.decode(returnData, (uint256));
    }

    function _execute_transfer(uint256 amount) internal {
        _executeTransaction(USDC, abi.encodeWithSelector(ERC20.transfer.selector, address(this), amount));
    }

    ///////////////////////////////////////////////////////////////
    /// --- SETTERS
    ///////////////////////////////////////////////////////////////

    function setMultiplier(uint256 _multiplier) external onlyGovernance {
        multiplier = _multiplier;
    }

    function setVeBoost(address _veBoost) external onlyGovernance {
        veBoost = IVeBoost(_veBoost);
    }

    function setVeBoostDelegation(address _veBoostDelegation) external onlyGovernance {
        veBoostDelegation = IVeBoostDelegation(_veBoostDelegation);
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
