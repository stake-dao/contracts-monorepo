// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Common} from "@address-book/src/CommonEthereum.sol";
import {PendleLocker, PendleProtocol} from "@address-book/src/PendleEthereum.sol";
import {IFeeReceiver} from "common/interfaces/IFeeReceiver.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {AccumulatorDripping} from "src/AccumulatorDripping.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {IPendleFeeDistributor} from "src/interfaces/IPendleFeeDistributor.sol";
import {SafeModule} from "@shared/safe/SafeModule.sol";

/// @title PendleAccumulator
/// @notice This contract is used to claim all the rewards the locker has received
///         from the different reward pools before sending them to Stake DAO's Liquidity Gauge (v4)
/// @dev This contract is the authorized distributor of the WETH and PENDLE rewards in the gauge
/// @author StakeDAO
/// @custom:contact contact@stakedao.org

contract PendleAccumulator is AccumulatorDripping, SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    address public constant token = PendleProtocol.PENDLE;
    address public constant veToken = PendleProtocol.VEPENDLE;

    /// @notice Base fee (10_000 = 100%)
    uint256 private constant BASE_FEE = 10_000;

    address public constant FEE_DISTRIBUTOR = PendleProtocol.FEE_DISTRIBUTOR;

    ///////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////

    /// @notice If false, the voters rewards will be distributed to the gauge
    bool public transferVotersRewards;

    /// @notice Address to receive the voters rewards.
    address public votesRewardRecipient;

    ////////////////////////////////////////////////////////////////
    /// --- ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when there is no balance to claim.
    error NO_BALANCE();

    /// @notice Error emitted when the claim is not successful.
    error NOT_CLAIMED_ALL();

    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    /// @notice Initializes the Accumulator
    /// @param _gauge Address of the sdPENDLE-gauge contract
    /// @param _locker Address of the Stake DAO Pendle Locker contract
    /// @param _governance Address of the governance contract
    /// @param _gateway Address of the gateway contract
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    ///
    ///      Here are some hardcoded parameters automatically set by the contract:
    ///      - WETH is the reward token
    ///      - PENDLE is the token
    ///      - VePENDLE is the veToken
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _gauge, address _locker, address _governance, address _gateway)
        AccumulatorDripping(
            _gauge,
            Common.WETH, // reward token
            _locker,
            _governance,
            4 // distribution length (in weeks)
        )
        SafeModule(_gateway)
    {
        // @dev: Legacy lockers (before v4) used to claim fees from the strategy contract
        //       In v4, fees are claimed by calling the unique accountant contract.
        //       Here we initially set the already deployed strategy contract to smoothen the migration
        accountant = PendleLocker.STRATEGY;

        // Give full approval to the gauge for the WETH and PENDLE tokens
        SafeTransferLib.safeApprove(Common.WETH, gauge, type(uint256).max);
        SafeTransferLib.safeApprove(PendleProtocol.PENDLE, gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Make the locker claim all the reward tokens before depositing them to the Liquidity Gauge (v4)
    /// @param _pools Array of pools to claim rewards from
    /// @custom:throws CampaignNotOver if this function is called when the current campaign is still ongoing
    function claimAndNotifyAll(address[] memory _pools) external {
        // Tell the Strategy to send the fees accrued by it to the fee receiver
        _claimAccumulatedFee();

        // Check the historical rewards.
        uint256 totalAccrued = IPendleFeeDistributor(FEE_DISTRIBUTOR).getProtocolTotalAccrued(address(locker));

        // Check the claimed rewards.
        uint256 claimed = IPendleFeeDistributor(FEE_DISTRIBUTOR).claimed(address(locker));

        // Check how many native reward are claimable.
        address[] memory vePendle = new address[](1);
        vePendle[0] = veToken;
        uint256 nativeRewardClaimable =
            IPendleFeeDistributor(FEE_DISTRIBUTOR).getProtocolClaimables(address(locker), vePendle)[0];

        // Claim the rewards from the pools to this contract and wrap them into wETH
        uint256 totalReward = _claimReward(_pools);

        // Ensure the total claimed reward is correct
        // @dev There's 1e4 wei of tolerance to avoid rounding errors because of a mistake in the Pendle FEE_DISTRIBUTOR contract.
        if (totalReward + 1e4 < totalAccrued - claimed) revert NOT_CLAIMED_ALL();

        // Start a new distribution campaign of `AccumulatorDripping.periodLength` weeks
        startNewDistribution();

        // Charge the fee on the total reward.
        totalReward -= _chargeFee(rewardToken, totalReward);

        // If the voters rewards must be transferred to the recipient, do it.
        if (transferVotersRewards) {
            uint256 votersTotalReward = totalReward - nativeRewardClaimable;
            // transfer the amount without charging fees
            SafeTransferLib.safeTransfer(rewardToken, votesRewardRecipient, votersTotalReward);
        }

        // Notify the rewards to the Liquidity Gauge (V4)
        // We set 0 as the amount to notify, because the overriden version of `_notifyReward` is charged for
        // calculating the exact amount to deposit into the gauge
        _notifyReward({tokenReward: rewardToken, amount: 0});
        _notifyReward({tokenReward: token, amount: 0});
    }

    /// @notice Notify the new reward to the LGV4
    /// @param tokenReward token to notify
    /// @param amount amount to notify
    function _notifyReward(address tokenReward, uint256 amount) internal override {
        // Split fees for the specified token using the fee receiver contract
        // Function not permissionless, to prevent sending to that accumulator and re-splitting (_chargeFee)
        if (feeReceiver != address(0)) IFeeReceiver(feeReceiver).split(tokenReward);

        // If the reward is the reward token, set the reward for the current period
        if (tokenReward == rewardToken) {
            amount = calculateDistributableReward();

            // If there are some rewards to distribute, start a new epoch
            if (amount != 0) advanceDistributionStep();
        } else {
            amount = ERC20(tokenReward).balanceOf(address(this));
        }

        if (amount == 0) return;
        ILiquidityGauge(gauge).deposit_reward_token(tokenReward, amount);
    }

    function _getLocker() internal view override returns (address) {
        return locker;
    }

    ////////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Claim locker's rewards to this contract
    /// @dev The `ETH` rewards are wrapped into `WETH`
    /// @param _pools pools to claim the rewards from
    function _claimReward(address[] memory _pools) internal returns (uint256 claimed) {
        uint256 balanceBefore = address(this).balance;
        _execute_claimRewards(_pools);

        // Wrap ETHs to WETHs
        claimed = address(this).balance - balanceBefore;
        if (claimed == 0) revert NO_BALANCE();
        IWETH(rewardToken).deposit{value: address(this).balance}();
    }

    ////////////////////////////////////////////////////////////////
    /// --- SAFE MODULE RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _execute_claimRewards(address[] memory _pools) internal {
        _executeTransaction(
            FEE_DISTRIBUTOR, abi.encodeWithSelector(IPendleFeeDistributor.claimProtocol.selector, address(this), _pools)
        );
    }

    ///////////////////////////////////////////////////////////////
    /// --- SETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Set the address to receive the voters rewards
    /// @param _votesRewardRecipient address to receive the voters rewards
    function setVotesRewardRecipient(address _votesRewardRecipient) external onlyGovernance {
        votesRewardRecipient = _votesRewardRecipient;
    }

    /// @notice Set if the voters rewards will be distributed to the gauge
    /// @param _transferVotersRewards if true, the voters rewards will be distributed to the gauge
    function setTransferVotersRewards(bool _transferVotersRewards) external onlyGovernance {
        transferVotersRewards = _transferVotersRewards;
    }

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    function version() external pure virtual override returns (string memory) {
        return "3.1.0";
    }

    function name() external view virtual override returns (string memory) {
        return type(PendleAccumulator).name;
    }
}

interface IWETH {
    function deposit() external payable;
}
