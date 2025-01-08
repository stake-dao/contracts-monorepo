// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

enum Operation {
    Call,
    DelegateCall
}

interface ISpectraVoter {
    function length() external view returns(uint256);
    function poolIds(uint256 poolId) external view returns(uint160);
    function poolToBribe(uint160 poolId) external view returns(address);
}

interface ISpectraVotingReward {
    function earned(address ve, address token, uint256 tokenId) external view returns(uint256);
    function rewardsListLength() external view returns(uint256);
    function rewards(uint256 i) external view returns(address);
    function getReward(address ve, uint256 tokenId, address[] memory tokens) external;
}

interface ISpectraGovernance {
    function poolsData(uint160 poolId) external view returns(address,uint256,bool);
}

interface ISafe {
    /// @dev Allows a Module to execute a Safe transaction without any further confirmations.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction.
    function execTransactionFromModule(address to, uint256 value, bytes calldata data, Operation operation) external returns (bool success);
}

contract SpectraVotingClaimer {
    /// @notice The address which will be able to perform the claim
    address public owner;

    /// @notice Address which will receive our funds
    address immutable recipient;

    address immutable SPECTRA_VOTER = address(0x174a1f4135Fab6e7B6Dbe207fF557DFF14799D33);
    address immutable SPECTRA_VE_NFT = address(0x6a89228055C7C28430692E342F149f37462B478B);
    address immutable SPECTRA_GOVERNANCE = address(0xa3eeA13183421c9A8BDA0BDEe191B70De8CA445D);
    address immutable SD_SAFE = address(0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765);

    /// @notice The Stake DAO NFT ID which owns the voting power
    uint256 immutable SD_SPECTRA_NFT_ID = 592;

    /// @notice Event emitted when a claim occured
    /// @param tokenAddress Address that was claimed.
    /// @param poolAddress Address that we claimed to.
    /// @param poolId Pool id that we claimed to.
    /// @param chainId The pool chain id.
    /// @param amount Amount claimed.
    /// @param timestamp The claim timestamp 
    event Claimed(address tokenAddress, address poolAddress, uint160 poolId, uint256 chainId, uint256 amount, uint256 timestamp);

    constructor(address _recipient) {
        owner = msg.sender;
        recipient = _recipient;
    }

    /// @notice Claim pending Spectra voting rewards
    /// @dev Can be called only by the current owner and recipient address mut not be ZERO
    function claim() external onlyOwner {
        if(recipient == address(0)) revert ZERO_ADDRESS();

        ISpectraVoter voter = ISpectraVoter(SPECTRA_VOTER);
        uint256 poolLength = voter.length();

        for(uint256 i = 0; i < poolLength; i++) {
            uint160 poolId = voter.poolIds(i);
            address votingRewardAddress = voter.poolToBribe(poolId);
            address[] memory rewardTokens = _getTokenRewards(votingRewardAddress);

            for(uint256 a = 0; a < rewardTokens.length; a++) {
                // Check if we have something to claim
                uint256 earned = ISpectraVotingReward(votingRewardAddress).earned(SPECTRA_VE_NFT, rewardTokens[a], SD_SPECTRA_NFT_ID);
                if(earned == 0) {
                    continue;
                }

                // Claim rewards
                // Rewards will be send to our MS
                _claim(votingRewardAddress, rewardTokens[a]);

                // Transfer rewards to our recipient
                _transferToRecipient(rewardTokens[a], earned);

                // Fetch pool address and chain id
                (address poolAddress, uint256 chainId,) = ISpectraGovernance(SPECTRA_GOVERNANCE).poolsData(poolId);

                // Emit an event to track it (help for the distribution)
                emit Claimed(rewardTokens[a], poolAddress, poolId, chainId, earned, block.timestamp);
            }
            
        }
    }

    /// @notice Get all token rewards associated to a voting reward contract
    /// @param votingRewardAddress Address to the voting reward
    function _getTokenRewards(address votingRewardAddress) internal view returns(address[] memory) {
        ISpectraVotingReward votingReward = ISpectraVotingReward(votingRewardAddress);
        uint256 rewardTokensLength = votingReward.rewardsListLength();
        
        address[] memory rewardTokens = new address[](rewardTokensLength);
        for(uint256 i = 0; i < rewardTokensLength; i++) {
            rewardTokens[i] = votingReward.rewards(i);
        }

        return rewardTokens;
    }

    /// @notice Send a transaction to the safe to claim voting rewards
    /// @dev Should be called only by the owner
    /// @param votingRewardAddress Address to the voting reward where the claim will happened
    /// @param reward Reward address to claim
    function _claim(address votingRewardAddress, address reward) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = reward;

        bytes memory data = abi.encodeWithSignature("getReward(address,uint256,address[])", SPECTRA_VE_NFT, SD_SPECTRA_NFT_ID, tokens);
        require(ISafe(SD_SAFE).execTransactionFromModule(votingRewardAddress, 0, data, Operation.Call), "Could not execute claim");
    }

    /// @notice Send some tokens to the recipient
    /// @dev Should be called only by the owner and the amount should be what we claimed just before
    /// @param token Token address to transfer
    /// @param amount Amount to transfer
    function _transferToRecipient(address token, uint256 amount) internal {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", payable(recipient), amount);
        require(ISafe(SD_SAFE).execTransactionFromModule(token, 0, data, Operation.Call), "Could not execute token transfer");
    }

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when an onlyOwner function has called by a different address
    error OWNER();

    /// @notice Error emitted when a zero address is pass
    error ZERO_ADDRESS();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Modifier to check if the caller is the owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert OWNER();
        _;
    }

    /// @notice Set a new owner that can accept it
    /// @dev Can be called only by the current owner
    /// @param _newOwner new owner address
    function transferOwner(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert ZERO_ADDRESS();
        owner = _newOwner;
    }
}