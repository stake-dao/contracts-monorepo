// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/depositor/BaseDepositor.sol";
import {ISdZeroLocker} from "src/common/interfaces/zerolend/ISdZeroLocker.sol";

/// @title BaseDepositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is BaseDepositor {
    constructor(address _token, address _locker, address _minter, address _gauge)
        BaseDepositor(_token, _locker, _minter, _gauge, 4 * 365 days)
    {}

    // @dev msg.sender needs to allow approve the locker
    // TODO natspecs
    function joinStakeDaoLocker(uint256[] calldata _tokenIds) external {
        uint256 amount = ISdZeroLocker(locker).joinStakeDaoLocker(msg.sender, _tokenIds);
        ITokenMinter(minter).mint(msg.sender, amount);
    }
}
