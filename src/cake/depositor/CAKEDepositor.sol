// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/base/depositor/DepositorV4.sol";

/// @title Cake Depositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract CAKEDepositor is DepositorV4 {
    /// @notice Throws if caller is not the Locker contract.
    error LOCKER();

    modifier onlyLocker() {
        if (msg.sender != locker) revert LOCKER();
        _;
    }

    /// @notice Constructor
    /// @param _token token to deposit
    /// @param _locker locker
    /// @param _minter sdToken
    /// @param _gauge sd gauge
    constructor(address _token, address _locker, address _minter, address _gauge)
        DepositorV4(_token, _locker, _minter, _gauge, (209 * 1 weeks) - 1)
    {}

    /// @notice mint sdCAKE for the delegator
    /// @param _user Delegator
    /// @param _amount Amount to mint
    function mintForCakeDelegator(address _user, uint256 _amount) external onlyLocker {
        /// Mint sdToken to this contract.
        ITokenMinter(minter).mint(address(this), _amount);

        /// Deposit sdToken into gauge for _user.
        ILiquidityGauge(gauge).deposit(_amount, _user);

        emit Deposited(msg.sender, _user, _amount, true, true);
    }
}
