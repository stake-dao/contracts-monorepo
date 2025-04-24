// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Pendle} from "address-book/src/protocols/1.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {IFeeReceiver} from "common/interfaces/IFeeReceiver.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {IPendleFeeDistributor} from "src/common/interfaces/IPendleFeeDistributor.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";
import {PENDLE as PendleProtocol} from "address-book/src/lockers/1.sol";

/// @title PendleAccumulator
/// @notice A contract that accumulates Pendle rewards and notifies them to the sdPENDLE gauge
/// @author StakeDAO
contract PendleAccumulator is BaseAccumulator, SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Base fee (10_000 = 100%)
    uint256 private constant BASE_FEE = 10_000;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant PENDLE = Pendle.PENDLE;
    address public constant VE_PENDLE = Pendle.VEPENDLE;
    address public constant FEE_DISTRIBUTOR = Pendle.FEE_DISTRIBUTOR;

    ///////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////

    /// @notice Period to add on each claim
    uint256 public periodsToAdd = 4;

    /// @notice WETH Rewards period to notify.
    uint256 public remainingPeriods;

    /// @notice If false, the voters rewards will be distributed to the gauge
    bool public transferVotersRewards;

    /// @notice Address to receive the voters rewards.
    address public votesRewardRecipient;

    /// @notice Rewards for the period.
    mapping(uint256 period => uint256 rewardAmount) public rewards;

    ////////////////////////////////////////////////////////////////
    /// --- ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when a token not supported is used.
    error WRONG_TOKEN();

    /// @notice Error emitted when there is no balance to claim.
    error NO_REWARD();

    /// @notice Error emitted when there is no balance to claim.
    error NO_BALANCE();

    /// @notice Error emitted when the claim is not successful.
    error NOT_CLAIMED_ALL();

    /// @notice Error emitted when the reward is ongoing.
    error ONGOING_REWARD();

    ////////////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    ////////////////////////////////////////////////////////////

    /// @notice Initializes the Accumulator
    /// @param _gauge Address of the sdPENDLE-gauge contract
    /// @param _locker Address of the Stake DAO Pendle Locker contract
    /// @param _governance Address of the governance contract
    constructor(address _gauge, address _locker, address _governance, address _gateway)
        BaseAccumulator(_gauge, WETH, _locker, _governance)
        SafeModule(_gateway)
    {
        strategy = PendleProtocol.STRATEGY;

        // Give full approval to the gauge for the WETH and PENDLE tokens
        SafeTransferLib.safeApprove(WETH, gauge, type(uint256).max);
        SafeTransferLib.safeApprove(PENDLE, gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Make the locker claim all the reward tokens before depositing them to the Liquidity Gauge (v4)
    /// @param _pools Array of pools to claim rewards from
    function claimAndNotifyAll(address[] memory _pools) external {
        // Tell the Strategy to send the fees accrued by it to the fee receiver
        _claimFeeStrategy();

        // Check the historical rewards.
        uint256 totalAccrued = IPendleFeeDistributor(FEE_DISTRIBUTOR).getProtocolTotalAccrued(address(locker));

        // Check the claimed rewards.
        uint256 claimed = IPendleFeeDistributor(FEE_DISTRIBUTOR).claimed(address(locker));

        // Check how many native reward are claimable.
        address[] memory vePendle = new address[](1);
        vePendle[0] = VE_PENDLE;
        uint256 nativeRewardClaimable =
            IPendleFeeDistributor(FEE_DISTRIBUTOR).getProtocolClaimables(address(locker), vePendle)[0];

        // Claim the rewards from the pools to this contract and wrap them into wETH
        uint256 totalReward = _claimReward(_pools);

        // Ensure the total claimed reward is correct
        // @dev There's 1e4 wei of tolerance to avoid rounding errors because of a mistake in the Pendle FEE_DISTRIBUTOR contract.
        if (totalReward + 1e4 < totalAccrued - claimed) revert NOT_CLAIMED_ALL();

        // Update the remaining periods.
        remainingPeriods += periodsToAdd;

        // Charge the fee on the total reward.
        totalReward -= _chargeFee(WETH, totalReward);

        // If the voters rewards must be transferred to the recipient, do it.
        if (transferVotersRewards) {
            uint256 votersTotalReward = totalReward - nativeRewardClaimable;
            // transfer the amount without charging fees
            SafeTransferLib.safeTransfer(WETH, votesRewardRecipient, votersTotalReward);
        }

        // Notify the rewards to the Liquidity Gauge (V4)
        // We set 0 as the amount to notify, because the overriden version of `_notifyReward` is charged for
        // calculating the exact amount to deposit into the gauge
        _notifyReward(WETH, 0, false);
        _notifyReward(PENDLE, 0, true);

        // legacy: just in case, but it shouldn't be needed anymore.
        _distributeSDT();
    }

    /// @notice Notify the new reward to the LGV4
    /// @param tokenReward token to notify
    /// @param amount amount to notify
    /// @param claimFeeStrategy if pull tokens from the fee receiver or not (tokens already in that contract)
    function _notifyReward(address tokenReward, uint256 amount, bool claimFeeStrategy) internal override {
        if (claimFeeStrategy && feeReceiver != address(0)) {
            // Split fees for the specified token using the fee receiver contract
            // Function not permissionless, to prevent sending to that accumulator and re-splitting (_chargeFee)
            IFeeReceiver(feeReceiver).split(tokenReward);
        }

        if (tokenReward == WETH && remainingPeriods != 0) {
            uint256 currentWeek = block.timestamp * 1 weeks / 1 weeks;
            if (rewards[currentWeek] != 0) revert ONGOING_REWARD();

            amount = ERC20(WETH).balanceOf(address(this)) / remainingPeriods;
            rewards[currentWeek] = amount;

            remainingPeriods -= 1;
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
        IWETH(WETH).deposit{value: address(this).balance}();
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

    /// @notice Set the number of periods to add to the remaining periods at each claim
    /// @param _periodsToAdd number of periods to add
    function setPeriodsToAdd(uint256 _periodsToAdd) external onlyGovernance {
        periodsToAdd = _periodsToAdd;
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
