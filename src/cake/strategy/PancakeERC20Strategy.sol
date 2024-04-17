// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IExecutor} from "src/base/interfaces/IExecutor.sol";
import {ICakeV2Wrapper} from "src/base/interfaces/ICakeV2Wrapper.sol";
import {Strategy} from "src/base/strategy/Strategy.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @notice Pancake ERC20 strategy module, it interacts with the Cake Locker via the Executor.
contract PancakeERC20Strategy is Strategy {
    IExecutor public immutable executor;

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

    function _depositIntoLocker(address _asset, address _gauge, uint256 _amount) internal override {
        // Transfer the LP token to the Locker.
        SafeTransferLib.safeTransfer(_asset, address(locker), _amount);

        // deposit, no harvest
        bytes memory depositData = abi.encodeWithSignature("deposit(uint256,bool)", _amount, true);

        (bool success,) = executor.callExecuteTo(address(locker), _gauge, 0, depositData);
        if (!success) revert LOW_LEVEL_CALL_FAILED();
    }

    function _withdrawFromLocker(address _asset, address _gauge, uint256 _amount) internal override {
        // deposit, no harvest
        bytes memory withdrawData = abi.encodeWithSignature("withdraw(uint256,bool)", _amount, true);

        (bool success,) = executor.callExecuteTo(address(locker), _gauge, 0, withdrawData);
        if (!success) revert LOW_LEVEL_CALL_FAILED();

        // Transfer the _asset_ from the Locker to this contract.
        _transferFromLocker(_asset, address(this), _amount);
    }

    function _transferFromLocker(address _asset, address _recipient, uint256 _amount) internal override {
        bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", _recipient, _amount);
        (bool success,) = executor.callExecuteTo(address(locker), _asset, 0, transferData);
        if (!success) revert LOW_LEVEL_CALL_FAILED();
    }

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

    function _claimNativeRewards() internal override {}

    function _claimExtraRewards(address, address) internal pure override returns (uint256) {
        return 0;
    }

    function setGauge(address _token, address _gauge) external override onlyGovernanceOrFactory {
        if (_token == address(0)) revert ADDRESS_NULL();
        if (_gauge == address(0)) revert ADDRESS_NULL();

        gauges[_token] = _gauge;

        bytes memory approveData = abi.encodeWithSignature("approve(address,uint256)", _gauge, type(uint256).max);
        (bool success,) = executor.callExecuteTo(address(locker), _token, 0, approveData);
        if (!success) revert LOW_LEVEL_CALL_FAILED();
    }

    function migrateLP(address) public override onlyVault {}

    function balanceOf(address _asset) public view override returns (uint256) {
        // Get the gauge address
        address gauge = gauges[_asset];
        if (gauge == address(0)) revert ADDRESS_NULL();

        ICakeV2Wrapper.UserInfo memory lockerInfo = ICakeV2Wrapper(gauge).userInfo(address(locker));
        return lockerInfo.amount;
    }
}
