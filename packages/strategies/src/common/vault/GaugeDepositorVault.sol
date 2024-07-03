// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "src/common/vault/Vault.sol";

/// @dev Support gauge deposit.
contract GaugeDepositorVault is Vault {
    /// @notice Deposit the yearn gauge token
    /// @param _receiver address to deposit for
    /// @param _amount amount to deposit
    function depositGaugeToken(address _receiver, uint256 _amount) external {
        // check gauge token
        address gauge = strategy().gauges(address(token()));
        //ERC20(gauge).transferFrom
        SafeTransferLib.safeTransferFrom(gauge, msg.sender, strategy().locker(), _amount);

        /// Mint amount equivalent to the amount deposited.
        _mint(address(this), _amount);

        /// Deposit for the receiver in the reward distributor gauge.
        liquidityGauge().deposit(_amount, _receiver);
    }
}
