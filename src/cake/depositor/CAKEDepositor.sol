// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/depositor/DepositorV4.sol";

/// @title Cake Depositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract CAKEDepositor is DepositorV4 {
    error LOCKER();

    modifier onlyLocker() {
        if (msg.sender != locker) revert LOCKER();
        _;
    }

    constructor(address _token, address _locker, address _minter, address _gauge)
        DepositorV4(_token, _locker, _minter, _gauge, (53 * 1 weeks) - 1)
    {}

    /// @notice mint sdCAKE for the delegator
    /// @param _user Delegator
    /// @param _amount Amount to mint
    function mintForCakeDelegator(address _user, uint256 _amount) external {
        /// Mint sdToken to this contract.
        ITokenMinter(minter).mint(address(this), _amount);

        /// Deposit sdToken into gauge for _user.
        ILiquidityGauge(gauge).deposit(_amount, _user);

        emit Deposited(msg.sender, _user, _amount, true, true);
    }
}
