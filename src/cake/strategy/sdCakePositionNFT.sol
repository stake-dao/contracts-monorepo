// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC721} from "solady/tokens/ERC721.sol";
import {ICakeStrategy} from "src/base/interfaces/ICakeStrategy.sol";

/// @notice CakePositionNFT
contract sdCakePositionNFT is ERC721 {
    /// @notice Address of the operator allowed to mint/burn NFT
    address public operator;

    /// @notice Error emitted when input address is null
    error AddressNull();

    /// @notice Error emitted on auth
    error OnlyOperator();

    /// @notice Event emitted when an operator is set
    event OperatorSet(address operator);

    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    constructor(address _operator) {
        if (operator == address(0)) revert AddressNull();
        operator = _operator;
    }

    /// @notice Mint a new NFT
    /// @param _to address of the NFT receiver
    /// @param _id nft id to use
    function mint(address _to, uint256 _id) external onlyOperator {
        _mint(_to, _id);
    }

    /// @notice Burn an NFT
    /// @param _id nft id
    function burn(uint256 _id) external onlyOperator {
        _burn(_id);
    }

    function transferFrom(address _from, address _to, uint256 _id) public payable override {
        // harvest the reward for the actual holder before tranfer it
        ICakeStrategy(operator).harvestNftAll(_id);
        super.transferFrom(_from, _to, _id);
    }

    /// @notice Set an operator allowed to mint/burn NFT
    /// @param _operator address of the operator
    function setOperator(address _operator) external onlyOperator {
        if (_operator == address(0)) revert AddressNull();
        emit OperatorSet(operator = _operator);
    }

    /// @notice Name of the contract
    function name() public view override returns (string memory) {
        return "sdCakePositionNFT";
    }

    /// @notice Symbol of the contract
    function symbol() public view override returns (string memory) {
        return "sdCPNFT";
    }

    /// @notice Token uri of the contract
    function tokenURI(uint256) public view override returns (string memory) {
        return "";
    }
}
