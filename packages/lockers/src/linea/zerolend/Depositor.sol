// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {BaseDepositor, ITokenMinter, ILiquidityGauge} from "src/common/depositor/BaseDepositor.sol";
import {ISdZeroLocker} from "src/common/interfaces/zerolend/stakedao/ISdZeroLocker.sol";

/// @title Stake DAO ZERO Depositor
/// @notice Contract that accepts ZERO and locks them in the Locker, minting sdZERO in return
/// @author StakeDAO
/// @custom:contact contact@stakedao.org
contract Depositor is BaseDepositor {
    /// @notice Constructor
    /// @param _token ZERO token.
    /// @param _locker SD locker.
    /// @param _minter sdZERO token.
    /// @param _gauge sdZERO-gauge contract.
    constructor(address _token, address _locker, address _minter, address _gauge)
        BaseDepositor(_token, _locker, _minter, _gauge, 4 * 365 days)
    {}

    /// @notice Deposit ZeroLend locker NFTs, and receive sdZero or sdZeroGauge in return.
    /// @param _tokenIds Token IDs to deposit.
    /// @param _stake Whether to stake the sdToken in the gauge.
    /// @param _user Address of the user to receive the sdToken.
    /// @dev In order to allow the transfer of the NFT tokens, msg.sender needs to give an approvalForAll to the locker.
    /// If stake is true, sdZero tokens are staked in the gauge which distributes rewards. If stake is false,
    /// sdZero tokens are sent to the user.
    function deposit(uint256[] calldata _tokenIds, bool _stake, address _user) external {
        if (_user == address(0)) revert ADDRESS_ZERO();

        uint256 _amount = ISdZeroLocker(locker).deposit(msg.sender, _tokenIds);

        // Mint sdtoken to the user if the gauge is not set.
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
