// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "src/base/locker/VeCRVLocker.sol";

/// @title  FXNLocker
/// @notice Locker contract for locking tokens for a period of time
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract FXNLocker is VeCRVLocker {
    constructor(address _depositor, address _token, address _veToken) VeCRVLocker(_depositor, _token, _veToken) {}

    function name() public override pure returns (string memory) {
        return "FXN Locker";
    }
}