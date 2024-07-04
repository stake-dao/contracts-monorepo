// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/locker/VeCRVLocker.sol";

/// @title  Locker
/// @notice Locker contract for locking tokens for a period of time
/// @author Stake DAO
/// @custom:contact contact@stakedao.org
contract Locker is VeCRVLocker {
    constructor(address _governance, address _token, address _veToken) VeCRVLocker(_governance, _token, _veToken) {}

    function name() public pure override returns (string memory) {
        return "FXN Locker";
    }
}
