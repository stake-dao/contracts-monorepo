// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Enum} from "@safe/contracts/Safe.sol";
import {BaseDepositor} from "src/common/depositor/BaseDepositor.sol";
import {ILocker} from "src/common/interfaces/spectra/stakedao/ILocker.sol";

/// @title Stake DAO Spectra Safe Module Depositor
/// @notice Defining logic to call execute as a Safe module on the locker
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract SafeModuleDepositor is BaseDepositor {
    constructor(address _token, address _locker, address _minter, address _gauge, uint256 _maxLockDuration)
        BaseDepositor(_token, _locker, _minter, _gauge, _maxLockDuration)
    {}

    ///////////////////////////////////////////////////////////////
    /// --- ERRORS
    ///////////////////////////////////////////////////////////////
    error ExecFromSafeModuleFailed();

    ///////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    function _executeTransaction(address _target, bytes memory _data) internal returns (bytes memory) {
        (bool _success, bytes memory returnData) =
            ILocker(locker).execTransactionFromModuleReturnData(_target, 0, _data, Enum.Operation.Call);
        if (!_success) revert ExecFromSafeModuleFailed();

        return returnData;
    }
}
