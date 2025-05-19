// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {YearnLocker, YearnProtocol} from "address-book/src/YearnEthereum.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {IFeeDistributor} from "src/common/interfaces/IFeeDistributor.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";

/// @title YearnAccumulator
/// @notice This contract is used to claim all the rewards the locker has received
///         from the different reward pools before sending them to Stake DAO's Liquidity Gauge (v4)
/// @dev This contract is the authorized distributor of the YFI and DEYFI rewards in the gauge
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract YearnAccumulator is BaseAccumulator, SafeModule {
    ///////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice YFI token address
    address public constant token = YearnProtocol.YFI;
    /// @notice YFI reward pool address
    address public constant YFI_REWARD_POOL = YearnProtocol.YFI_REWARD_POOL;
    /// @notice dYFI reward pool address
    address public constant DYFI_REWARD_POOL = YearnProtocol.DYFI_REWARD_POOL;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge Address of the sdYFI-gauge contract
    /// @param _locker Address of the sdYFI locker
    /// @param _governance Address of the governance
    /// @param _gateway Address of the gateway
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    ///
    ///      Here are some hardcoded parameters automatically set by the contract:
    ///      - YFI is the reward token
    ///      - YFI is the token
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _gauge, address _locker, address _governance, address _gateway)
        BaseAccumulator(_gauge, YearnProtocol.DYFI, _locker, _governance)
        SafeModule(_gateway)
    {
        // @dev: Legacy lockers (before v4) used to claim fees from the strategy contract
        //       In v4, fees are claimed by calling the unique accountant contract.
        //       Here we initially set the already deployed strategy contract to smoothen the migration
        accountant = YearnLocker.STRATEGY;

        // Give full approval to the gauge for the YFI and DYFI tokens
        SafeTransferLib.safeApprove(YearnProtocol.YFI, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(YearnProtocol.DYFI, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    function claimAndNotifyAll() external virtual override {
        claimAndNotifyAll(false);
    }

    /// @notice Make the locker claim all the reward tokens before depositing them to the Liquidity Gauge (v4)
    /// @param claimPenalty Whether to apply the penalty to the rewards
    function claimAndNotifyAll(bool claimPenalty) public {
        // 1. Claim locker's claimable YFI rewards and send them to this contract
        if (claimPenalty) {
            _execute_claim(YFI_REWARD_POOL);

            uint256 claimedYFI = IERC20(token).balanceOf(locker);
            if (claimedYFI != 0) _execute_transfer(token, claimedYFI);
        }

        // 2. Claim locker's claimable DYFI rewards and send them to this contract
        _execute_claim(DYFI_REWARD_POOL);
        uint256 claimedDYFI = IERC20(rewardToken).balanceOf(locker);
        if (claimedDYFI != 0) _execute_transfer(rewardToken, claimedDYFI);

        // 3. Tell the Strategy to send the accrued fees to the fee receiver
        _claimAccumulatedFee();

        // 4. Notify the rewards to the Liquidity Gauge (V4)
        notifyReward(token);
        notifyReward(rewardToken);
    }

    function _getLocker() internal view override returns (address) {
        return locker;
    }

    ////////////////////////////////////////////////////////////////
    /// --- SAFE MODULE RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _execute_claim(address pool) internal virtual {
        _executeTransaction(pool, abi.encodeWithSelector(IFeeDistributor.claim.selector));
    }

    function _execute_transfer(address _token, uint256 amount) internal virtual {
        _executeTransaction(_token, abi.encodeWithSelector(IERC20.transfer.selector, address(this), amount));
    }

    ///////////////////////////////////////////////////////////////
    /// --- GETTERS
    ///////////////////////////////////////////////////////////////

    function version() external pure virtual override returns (string memory) {
        return "4.0.0";
    }

    function name() external view virtual override returns (string memory) {
        return type(YearnAccumulator).name;
    }
}
