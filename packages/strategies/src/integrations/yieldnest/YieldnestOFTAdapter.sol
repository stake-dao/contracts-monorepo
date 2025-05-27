/// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {OFTAdapter} from "layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Common} from "address-book/src/CommonEthereum.sol";

/// @title asdYND Yieldnest OFTAdapter
/// @notice This contract enables bridging of asdYND tokens from Ethereum mainnet to BSC using LayerZero V2.
/// @dev This contract is a LayerZero OFTAdapter for the asdYND token (Autocompounded Stake DAO YND shares).
///      It allows users to lock their asdYND tokens on mainnet and bridge them to BSC, where they are minted as omnichain asdYND tokens.
///
///      LayerZero is an interoperability protocol for secure cross-chain messaging and bridging. It allows tokens to move between networks
///      without wrapping or middlechains, using a unified supply model.
///
///      How to lock and bridge asdYND to BSC
///         1. Approve this contract to spend your asdYND tokens.
///         2. Call the `send` function (inherited from OFTAdapter) with the appropriate parameters to bridge your tokens to BSC.
///            - The contract will lock your asdYND tokens on mainnet and initiate a LayerZero message to BSC.
///         3. On BSC, the paired OFT contract will mint the equivalent amount of asdYND tokens to the recipient.
///
///      Where are tokens bridged to?
///          - Currently, this contract is configured to bridge asdYND tokens only to the BSC chain (destination chain).
///          - The BSC OFT contract address must be set as a trusted remote in LayerZero configuration.
///
///      For more details on LayerZero and OFT bridging, see:
///      https:///docs.layerzero.network/v2/developers/evm/oft/quickstart
contract YieldnestOFTAdapter is OFTAdapter {
    /// @notice Deploys the Yieldnest OFTAdapter for asdYND bridging.
    /// @param _token The address of the asdYND ERC20 token to be locked and bridged.
    /// @param _owner The contract owner (admin for LayerZero configuration).
    constructor(address _token, address _owner)
        OFTAdapter(_token, Common.LAYERZERO_ENDPOINT, _owner)
        Ownable(msg.sender)
    {}
}
