// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldnestProtocol} from "@address-book/src/YieldnestEthereum.sol";
import {AutocompoundedVault} from "src/AutocompoundedVault.sol";

/// @title Autocompounded Stake DAO YND Vault
/// @notice This contract is a fully compliant ERC4626 streaming yield-bearing vault for sdYND tokens.
///         The rewards are streamed linearly over a fixed period and the vault is autocompounded.
contract YieldnestAutocompoundedVault is AutocompoundedVault {
    /// @notice Initialize the the streaming period, the asset and the shares token
    /// @dev sdYND is the asset contract while asdYND is the shares token
    /// @param _owner The owner of the vault
    constructor(address _owner)
        AutocompoundedVault(7 days, IERC20(YieldnestProtocol.SDYND), "Autocompounded Stake DAO YND", "asdYND", _owner)
    {}
}
