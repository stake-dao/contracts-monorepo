// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FXS as FraxMainnet} from "address-book/src/lockers/1.sol";
import {Frax} from "address-book/src/protocols/252.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {IYieldDistributor} from "src/common/interfaces/IYieldDistributor.sol";
import {SafeModule} from "src/common/utils/SafeModule.sol";
import {FXTLDelegation} from "src/fraxtal/FXTLDelegation.sol";

/// @title A contract that accumulates FXS rewards and notifies them to the LGV4
/// @author StakeDAO
contract FraxAccumulator is BaseAccumulator, FXTLDelegation, SafeModule {
    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    /// @notice Frax ethereum locker
    address public constant ETH_LOCKER = FraxMainnet.LOCKER;

    //////////////////////////////////////////////////////
    /// --- STORAGE
    //////////////////////////////////////////////////////

    /// @notice Frax yield distributor
    address public yieldDistributor;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _gauge fraxtal gauge
    /// @param _locker fraxtal locker
    /// @param _governance governance
    /// @param _delegationRegistry delegation registry
    /// @param _initialDelegate initial delegate
    /// @param _gateway Address of the gateway
    /// @dev If `locker` and `gateway` are the same, internal calls will be done directly on the target from the gateway.
    ///      Otherwise, the gateway will pass the execution to the `locker` to call the target contracts.
    ///
    ///      Here are some hardcoded parameters automatically set by the contract:
    ///         - FXS is the reward token
    /// @custom:throws InvalidGateway if the provided gateway is a zero address
    /// @custom:throws FXTLDelegationFailed if the delegation fails
    constructor(
        address _gauge,
        address _locker,
        address _governance,
        address _delegationRegistry,
        address _initialDelegate,
        address _gateway
    )
        BaseAccumulator(
            _gauge,
            Frax.FXS, // rewardToken
            _locker,
            _governance
        )
        FXTLDelegation(_delegationRegistry, _initialDelegate)
        SafeModule(_gateway)
    {
        // Set the initial yield distributor
        yieldDistributor = Frax.YIELD_DISTRIBUTOR;

        // Give full approval to the gauge for the FXS token
        SafeTransferLib.safeApprove(Frax.FXS, _gauge, type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Claims all rewards tokens for the locker and notify them to the LGV4
    function claimAndNotifyAll() external override {
        // Sending accountant fees to fee receiver
        if (accountant != address(0)) _claimAccumulatedFee();

        // Claim FXS reward for L1's veFXS bridged, on behalf of the eth locker
        IYieldDistributor(yieldDistributor).getYieldThirdParty(ETH_LOCKER);

        // Tell the locker to claim the FXS yield
        _execute_getYield();
        uint256 lockerFXSBalance = ERC20(rewardToken).balanceOf(locker);

        // Tell the locker to transfer the FXS yield to this contract if any
        if (lockerFXSBalance != 0) _execute_transfer(lockerFXSBalance);

        // Notify FXS to the gauge.
        notifyReward(rewardToken);
    }

    ////////////////////////////////////////////////////////////////
    /// --- SAFE MODULE RELATED FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _execute_getYield() internal virtual {
        _executeTransaction(yieldDistributor, abi.encodeWithSelector(IYieldDistributor.getYield.selector));
    }

    function _execute_transfer(uint256 amount) internal virtual {
        _executeTransaction(rewardToken, abi.encodeWithSelector(ERC20.transfer.selector, address(this), amount));
    }

    ////////////////////////////////////////////////////////////////
    /// --- SETTERS
    ///////////////////////////////////////////////////////////////

    /// @notice Set frax yield distributor
    /// @param _yieldDistributor Address of the frax yield distributor
    function setYieldDistributor(address _yieldDistributor) external onlyGovernance {
        yieldDistributor = _yieldDistributor;
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
        return type(FraxAccumulator).name;
    }
}
