// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "src/common/depositor/BaseDepositor.sol";
import {ISdZeroLocker} from "src/common/interfaces/zerolend/stakedao/ISdZeroLocker.sol";

/// @title BaseDepositor
/// @notice Contract that accepts tokens and locks them in the Locker, minting sdToken in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is BaseDepositor {
    constructor(address _token, address _locker, address _minter, address _gauge)
        BaseDepositor(_token, _locker, _minter, _gauge, 4 * 365 days)
    {}

    /// @notice Deposit ZeroLend stake NFTs, and receive sdToken or sdTokenGauge in return.
    /// @param _tokenIds Token IDs to deposit.
    /// @param _stake Whether to stake the sdToken in the gauge.
    /// @param _user Address of the user to receive the sdToken.
    /// @dev In order to allow the transfer of the NFT tokens, msg.sender needs to give an approvalForAll to the locker.
    /// If the stake is true, the sdToken is staked in the gauge that distributes rewards. If the stake is false,
    /// the sdToken is sent to the user.
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
