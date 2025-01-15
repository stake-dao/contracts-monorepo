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
    function deposit(uint256[] calldata _tokenIds, bool _stake, address _user) external {
        if (_user == address(0)) revert ADDRESS_ZERO();

        uint256 _amount = ISdZeroLocker(locker).deposit(msg.sender, _tokenIds);

        // Mint sdtoken to the user if the gauge is not set
        if (_stake && gauge != address(0)) {
            /// Mint sdToken to this contract.
            ITokenMinter(minter).mint(address(this), _amount);

            /// Deposit sdToken into gauge for _user.
            ILiquidityGauge(gauge).deposit(_amount, _user);
        } else {
            /// Mint sdToken to _user.
            ITokenMinter(minter).mint(_user, _amount);
        }
    }
}
