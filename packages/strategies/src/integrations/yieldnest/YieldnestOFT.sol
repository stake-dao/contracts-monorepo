// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "layerzerolabs/oft-evm/contracts/OFT.sol";
import {Common} from "address-book/src/CommonBSC.sol";

/// @title asdYND Yieldnest OFT (BSC)
/// @notice This contract represents the omnichain asdYND token on BSC, enabling minting and burning via LayerZero V2 bridging.
///
/// @dev This contract is a LayerZero OFT (Omnichain Fungible Token) for asdYND (Autocompounded Stake DAO YND shares).
///      It allows users to receive asdYND tokens bridged from Ethereum mainnet and to bridge them back by burning.
///
///      LayerZero is an interoperability protocol for secure cross-chain messaging and bridging. It allows tokens to move between networks
///      without wrapping or middlechains, using a unified supply model.
///
///      What token is minted here?
///          - This contract mints and burns the omnichain asdYND ERC20 token on BSC.
///          - The token is minted when asdYND is bridged in from mainnet, and burned when bridging out.
///
///      How does bridging work?
///         1. On Ethereum mainnet, users lock asdYND tokens in the `YieldnestOFTAdapter` contract to initiate a bridge to BSC.
///         2. This contract receives a LayerZero message and mints the equivalent amount of asdYND tokens to the recipient on BSC.
///         3. To bridge back, users call the `send` function (inherited from OFT) to burn their asdYND tokens and initiate a bridge back to mainnet.
///
///     For more details on LayerZero and OFT bridging, see:
///     https://docs.layerzero.network/v2/developers/evm/oft/quickstart
contract YieldnestOFT is OFT {
    /// @notice Deploys the Yieldnest OFT for asdYND bridging on BSC.
    /// @param _delegate The admin for LayerZero configuration.
    /// @param _owner The owner of the contract
    constructor(address _delegate, address _owner)
        OFT("Autocompounded Stake DAO YND", "asdYND", Common.LAYERZERO_ENDPOINT, _delegate)
        Ownable(_owner)
    {}
}
