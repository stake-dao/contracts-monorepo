// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

interface ILaPoste {
    struct Token {
        address tokenAddress;
        uint256 amount;
    }

    struct TokenMetadata {
        string name;
        string symbol;
        uint8 decimals;
    }

    struct MessageParams {
        uint256 destinationChainId;
        address to;
        Token[] tokens;
        bytes payload;
    }

    struct Message {
        uint256 destinationChainId;
        address to;
        address sender;
        Token[] tokens;
        TokenMetadata[] tokenMetadata;
        bytes payload;
        uint256 nonce;
    }

    function tokenFactory() external view returns (address);

    function receiveMessage(uint256 chainId, bytes calldata payload) external;
    function sendMessage(MessageParams memory params, uint256 additionalGasLimit, address refundAddress)
        external
        payable;
}
