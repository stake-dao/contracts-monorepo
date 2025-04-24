// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Yearn} from "address-book/src/protocols/1.sol";
import {YFI as YearnProtocol} from "address-book/src/lockers/1.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {IFeeDistributor} from "src/common/interfaces/IFeeDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title YFI BaseAccumulator
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
    address public constant YFI = Yearn.YFI;
    /// @notice YFI reward pool address
    address public constant YFI_REWARD_POOL = Yearn.YFI_REWARD_POOL;
    /// @notice DFYI token address
    address public constant DYFI = Yearn.DYFI;
    /// @notice dYFI reward pool address
    address public constant DYFI_REWARD_POOL = Yearn.DYFI_REWARD_POOL;

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
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    constructor(address _gauge, address _locker, address _governance, address _gateway)
        BaseAccumulator(_gauge, DYFI, _locker, _governance)
        SafeModule(_gateway)
    {
        strategy = YearnProtocol.STRATEGY;

        // Give full approval to the gauge for the YFI and DYFI tokens
        SafeTransferLib.safeApprove(YFI, _gauge, type(uint256).max);
        SafeTransferLib.safeApprove(DYFI, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    function claimAndNotifyAll() external virtual override {
        claimAndNotifyAll(false);
    }

    /// @notice Make the locker claim all the reward tokens before depositing them to the Liquidity Gauge (v4)
    /// @dev This function automatically applies the penalty to the claimed rewards
    /// @param notifySDT Whether to notify the SDT or not. When true, it distributes the SDT to the gauge
    /// @param claimFeeStrategy Whether to send strategy fees to fee receiver
    function claimAndNotifyAll(bool notifySDT, bool claimFeeStrategy) external override {
        claimAndNotifyAll(notifySDT, claimFeeStrategy, true);
    }

    /// @notice Make the locker claim all the reward tokens before depositing them to the Liquidity Gauge (v4)
    /// @param claimPenalty Whether to apply the penalty to the rewards
    function claimAndNotifyAll(bool claimPenalty) public {
        // 1. Claim locker's claimable YFI rewards and send them to this contract
        if (claimPenalty) {
            _execute_claim(YFI_REWARD_POOL);

            uint256 claimedYFI = IERC20(YFI).balanceOf(locker);
            if (claimedYFI != 0) _execute_transfer(YFI, claimedYFI);
        }

        // 2. Claim locker's claimable DYFI rewards and send them to this contract
        _execute_claim(DYFI_REWARD_POOL);
        uint256 claimedDYFI = IERC20(DYFI).balanceOf(locker);
        if (claimedDYFI != 0) _execute_transfer(DYFI, claimedDYFI);

        // 3. Tell the Strategy to send the accrued fees to the fee receiver
        _claimFeeStrategy();

        // 4. Notify the rewards to the Liquidity Gauge (V4)
        notifyReward(YFI, false, false);
        notifyReward(DYFI, true, true);
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

    function _execute_transfer(address token, uint256 amount) internal virtual {
        _executeTransaction(token, abi.encodeWithSelector(IERC20.transfer.selector, address(this), amount));
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
