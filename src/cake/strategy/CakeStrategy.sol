// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {ERC721} from "solady/tokens/ERC721.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ILocker, SafeExecute, Strategy} from "src/base/strategy/Strategy.sol";

/// @notice Main access point of Cake Locker.
contract CakeStrategy is Strategy {
    using SafeExecute for ILocker;

    /// @notice PancakeSwap non fungible position manager.
    address public cakeNfpm = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;

    /// @notice PancakeSwap masterChef.
    address public cakeMc = 0x556B9306565093C855AEA9AE92A594704c2Cd59e;

    /// @notice Mapping of NFT stakers.
    mapping(uint256 => address) public nftStakers; // tokenId -> user

    error NotNftStaker();

    /// @notice throwed when the ERC721 hook has not called by cake nfpm
    error NotPancakeNFT();

    modifier onlyNftStaker(uint256 tokenId) {
        if (msg.sender != nftStakers[tokenId]) revert NotNftStaker();
        _;
    }

    /// @notice Constructor.
    /// @param _owner Address of the strategy owner.
    /// @param _locker Address of the locker.
    /// @param _veToken Address of the veToken.
    /// @param _rewardToken Address of the reward token.
    /// @param _minter Address of the platform minter.
    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}

    function initialize(address owner) external override {
        if (governance != address(0)) revert GOVERNANCE();
        governance = owner;
    }

    /// @notice Harvest reward for an NFT.
    /// @param _tokenId NFT id to harvest.
    function harvestNft(uint256 _tokenId) external {
        _harvestNft(_tokenId, msg.sender);
    }

    /// @notice Harvest reward for an NFT.
    /// @param _tokenId NFT id to harvest.
    /// @param _recipient reward receiver
    function harvestNft(uint256 _tokenId, address _recipient) external onlyNftStaker(_tokenId) {
        _harvestNft(_tokenId, _recipient);
    }

    /// @notice Internal function to harvest reward for an NFT.
    /// @param _tokenId NFT id to harvest.
    /// @param _recipient reward receiver
    function _harvestNft(uint256 _tokenId, address _recipient) internal {
        uint256 balanceBeforeHarvest = ERC20(rewardToken).balanceOf(address(locker));
        bytes memory harvestData = abi.encodeWithSignature("harvest(uint256,address)", _tokenId, address(locker));
        locker.safeExecute(cakeMc, 0, harvestData);
        uint256 reward = ERC20(rewardToken).balanceOf(address(locker)) - balanceBeforeHarvest;
        if (reward != 0) {
            // send the whole reward here
            bytes memory transferData = abi.encodeWithSignature("transfer(address,uint256)", address(this), reward);
            locker.safeExecute(rewardToken, 0, transferData);
            reward -= _chargeProtocolFees(reward);
            // send the reward - fees to the recipient
            SafeTransferLib.safeTransfer(rewardToken, _recipient, reward);
            //ERC20(rewardToken).transfer(_recipient, reward);
        }
    }

    /// @notice Withdraw the NFT sending it to the recipient.
    /// @param _tokenId NFT id to withdraw.
    function withdrawNft(uint256 _tokenId) external {
        _withdrawNft(_tokenId, msg.sender);
    }

    /// @notice Withdraw the NFT sending it to the recipient.
    /// @param _tokenId NFT id to withdraw.
    /// @param _recipient NFT receiver.
    function withdrawNft(uint256 _tokenId, address _recipient) external {
        _withdrawNft(_tokenId, _recipient);
    }

    /// @notice Internal function to withdraw the NFT sending it to the recipient.
    /// @param _tokenId NFT id to withdraw.
    /// @param _recipient NFT receiver
    function _withdrawNft(uint256 _tokenId, address _recipient) internal onlyNftStaker(_tokenId) {
        //if (msg.sender != stakers[_tokenId]) revert NotTheStaker();
        // withdraw the NFT from pancake masterchef, it will send it to the recipient
        bytes memory withdrawData = abi.encodeWithSignature("withdraw(uint256,address)", _tokenId, _recipient);
        locker.safeExecute(cakeMc, 0, withdrawData);
        nftStakers[_tokenId] = address(0);
    }

    /// @notice Hook triggered within safe function calls.
    /// @param _from NFT sender.
    /// @param _tokenId NFT id received
    function onERC721Received(address, address _from, uint256 _tokenId, bytes calldata) external {
        if (msg.sender != address(cakeNfpm)) revert NotPancakeNFT();
        // store the owner's tokenId
        nftStakers[_tokenId] = _from;
        // transfer the NFT to the cake locker using the non safe transfer to not trigger the hook
        ERC721(cakeNfpm).transferFrom(address(this), address(locker), _tokenId);
        // transfer the NFT to the pancake masterchef v3 via the locker using safe transfer to trigger the hook
        bytes memory safeTransferData =
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(this), cakeMc, _tokenId);
        locker.safeExecute(cakeNfpm, 0, safeTransferData);
    }

    function setCakeMc(address _cakeMc) external onlyGovernance {
        cakeMc = _cakeMc;
    }

    function setCakeNfpm(address _cakeNfpm) external onlyGovernance {
        cakeNfpm = _cakeNfpm;
    }
}
