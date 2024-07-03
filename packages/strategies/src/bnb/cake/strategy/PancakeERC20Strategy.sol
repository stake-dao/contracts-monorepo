// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IExecutor} from "src/common/interfaces/IExecutor.sol";
import {ICakeV2Wrapper} from "src/common/interfaces/ICakeV2Wrapper.sol";
import {Strategy} from "src/common/strategy/Strategy.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @notice Pancake ERC20 strategy module, it interacts with the Cake Locker via the Executor.
contract PancakeERC20Strategy is Strategy {
    /// @notice Executor contract.
    IExecutor public immutable executor;

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor.
    /// @param _owner Address of the owner.
    /// @param _locker Address of the pancake locker.
    /// @param _veToken Address of the veCAKE.
    /// @param _rewardToken Address of the reward token.
    /// @param _minter Address of the minter
    /// @param _executor Address of the executor
    constructor(
        address _owner,
        address _locker,
        address _veToken,
        address _rewardToken,
        address _minter,
        address _executor
    ) Strategy(_owner, _locker, _veToken, _rewardToken, _minter) {
        executor = IExecutor(_executor);
    }

    /// @notice Deposit into the gauge through the Locker.
    /// @param _asset Address of LP token to deposit.
    /// @param _gauge Address of Liqudity gauge corresponding to LP token.
    /// @param _amount Amount of LP token to deposit.
    function _depositIntoLocker(address _asset, address _gauge, uint256 _amount) internal override {
        // Transfer the LP token to the Locker.
        SafeTransferLib.safeTransfer(_asset, address(locker), _amount);

        // deposit, no harvest
        bytes memory depositData = abi.encodeWithSignature("deposit(uint256,bool)", _amount, true);

        (bool success,) = executor.callExecuteTo(address(locker), _gauge, 0, depositData);
        if (!success) revert LOW_LEVEL_CALL_FAILED();
    }

    /// @notice Withdraw from the gauge through the Locker.
    /// @param _asset Address of LP token to withdraw.
    /// @param _gauge Address of Liqudity gauge corresponding to LP token.
    /// @param _amount Amount of LP token to withdraw.
    function _withdrawFromLocker(address _asset, address _gauge, uint256 _amount) internal override {
        // deposit, no harvest
        bytes memory withdrawData = abi.encodeWithSignature("withdraw(uint256,bool)", _amount, true);

        (bool success,) = executor.callExecuteTo(address(locker), _gauge, 0, withdrawData);
        if (!success) revert LOW_LEVEL_CALL_FAILED();

        // Transfer the _asset_ from the Locker to this contract.
        _transferFromLocker(_asset, address(this), _amount);
    }

    /// @notice Transfer token from the loker to the recipient.
    /// @param _asset Address of token to transfer.
    /// @param _recipient Address of the recipient that will receive the tokens.
    /// @param _amount Amount of token to transfer.
    function _transferFromLocker(address _asset, address _recipient, uint256 _amount) internal override {
        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount);
        (bool success,) = executor.callExecuteTo(address(locker), _asset, 0, transferData);
        if (!success) revert LOW_LEVEL_CALL_FAILED();
    }

    /// @notice Claim `rewardToken` allocated for a gauge.
    /// @param _gauge Address of the liquidity gauge to claim for.
    function _claimRewardToken(address _gauge) internal override returns (uint256 claimed) {
        // Snapshot before claim.
        uint256 snapshotBalance = ERC20(rewardToken).balanceOf(address(locker));

        // Claim `rewardToken` from the Gauge.
        bytes memory harvestData = abi.encodeWithSignature("deposit(uint256,bool)", 0, false); // only harvest
        (bool success,) = executor.callExecuteTo(address(locker), _gauge, 0, harvestData);
        if (!success) revert LOW_LEVEL_CALL_FAILED();

        claimed = ERC20(rewardToken).balanceOf(address(locker)) - snapshotBalance;

        // Transfer the claimed amount to this contract.
        _transferFromLocker(rewardToken, address(this), claimed);
    }

    /// @notice Claim native reward (empty, it is managed by the accumulator).
    function _claimNativeRewards() internal override {}

    /// @notice Claim extra rewards from the locker. (it returns 0 because pancacake gauges don't support extra rewards).
    function _claimExtraRewards(address, address) internal pure override returns (uint256) {
        return 0;
    }

    /// @notice Set gauge address for a LP token.
    /// @param _token Address of LP token corresponding to `gauge`.
    /// @param _gauge Address of liquidity gauge corresponding to `token`.
    function setGauge(address _token, address _gauge) external override onlyGovernanceOrFactory {
        if (_token == address(0)) revert ADDRESS_NULL();
        if (_gauge == address(0)) revert ADDRESS_NULL();

        bool success;
        bytes memory approveData;

        /// Revoke approval for the old gauge.
        address oldGauge = gauges[_token];
        if (oldGauge != address(0)) {
            approveData = abi.encodeWithSignature("approve(address,uint256)", _gauge, 0);
            (success,) = executor.callExecuteTo(address(locker), _token, 0, approveData);
            if (!success) revert LOW_LEVEL_CALL_FAILED();
        }

        gauges[_token] = _gauge;

        approveData = abi.encodeWithSignature("approve(address,uint256)", _gauge, type(uint256).max);
        (success,) = executor.callExecuteTo(address(locker), _token, 0, approveData);
        if (!success) revert LOW_LEVEL_CALL_FAILED();
    }

    /// @notice Function in supports of a strategy migration (empty, it isn't required in pancake).
    function migrateLP(address) public override onlyVault {}

    /// @notice Get the `_asset` gauge locker's balance.
    /// @param _asset Address of LP token.
    function balanceOf(address _asset) public view override returns (uint256) {
        // Get the gauge address
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        ICakeV2Wrapper.UserInfo memory lockerInfo = ICakeV2Wrapper(gauge).userInfo(address(locker));
        return lockerInfo.amount;
    }
}
