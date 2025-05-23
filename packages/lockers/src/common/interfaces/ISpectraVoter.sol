// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISpectraVoter {
    /// @dev Total Voting Weights
    function totalWeight() external view returns (uint256);

    /// @dev Most number of pools one voter can vote for at once
    function maxVotingNum() external view returns (uint256);

    /// @dev The governance registry address
    function governanceRegistry() external view returns (address);

    /// @dev Pool => Fees and Bribes voting rewards deployment status
    function hasVotingRewards(uint160 _poolId) external view returns (bool);

    /// @dev Pool => Fees Voting Reward
    function poolToFees(uint160 _poolId) external view returns (address);

    /// @dev Pool => Bribes Voting Reward
    function poolToBribe(uint160 _poolId) external view returns (address);

    /// @dev Pool => Weights
    function weights(uint160 _poolId) external view returns (uint256);

    /// @dev NFT => Pool => Votes
    function votes(address _ve, uint256 tokenId, uint160 poolId) external view returns (uint256);

    /// @dev NFT => Pool => index of pool voted for by NFT => Votes
    function poolVote(address _ve, uint256 tokenId, uint256 index) external view returns (uint160);

    /// @dev NFT => Total voting weight of NFT
    function usedWeights(address _ve, uint256 tokenId) external view returns (uint256);

    /// @dev Nft => Timestamp of last vote (ensures single vote per epoch)
    function lastVoted(address _ve, uint256 tokenId) external view returns (uint256);

    /// @dev Token => Whitelisted status
    function isWhitelistedToken(address token) external view returns (bool);

    /// @dev TokenId => Whitelisted status
    function isWhitelistedNFT(address _ve, uint256 tokenId) external view returns (bool);

    /// @dev PoolId => Is voting authorized
    function isVoteAuthorized(uint160 _poolId) external view returns (bool);

    /// @notice Number of pools with a Gauge
    function length() external view returns (uint256);

    /// @notice Called by users to update voting balances in voting rewards contracts.
    /// @param _ve          Address of ve token.
    /// @param _tokenId Id of veNFT whose balance you wish to update.
    function poke(address _ve, uint256 _tokenId) external;

    /// @notice Called by users to vote for pools. Votes distributed proportionally based on weights.
    ///         Can only vote or deposit into a managed NFT once per epoch.
    ///         Can only vote for gauges that have not been killed.
    /// @dev Weights are distributed proportional to the sum of the weights in the array.
    ///      Throws if length of _poolVote and _weights do not match.
    /// @param _ve          Address of ve token.
    /// @param _tokenId     Id of veNFT you are voting with.
    /// @param _poolVote    Array of pool ids you are voting for.
    /// @param _weights     Weights of pools.
    function vote(address _ve, uint256 _tokenId, uint160[] calldata _poolVote, uint256[] calldata _weights) external;

    /// @notice Called by users to reset voting state. Required if you wish to make changes to
    ///         veNFT state (e.g. merge, split, deposit into managed etc).
    ///         Cannot reset in the same epoch that you voted in.
    ///         Can vote or deposit into a managed NFT again after reset.
    /// @param _ve          Address of ve token.
    /// @param _tokenId Id of veNFT you are reseting.
    function reset(address _ve, uint256 _tokenId) external;

    /// @notice Force reset a veNFT.
    /// @param _ve          Address of ve token.
    /// @param _tokenId     Id of veNFT you are reseting.
    /// @dev Throws if not called by VOTER_GOVERNOR_ROLE
    function forceReset(address _ve, uint256 _tokenId) external;

    /// @notice Called by users to deposit into a managed NFT.
    ///         Can only vote or deposit into a managed NFT once per epoch.
    ///         Note that NFTs deposited into a managed NFT will be re-locked
    ///         to the maximum lock time on withdrawal.
    /// @dev Throws if not approved or owner.
    ///      Throws if managed NFT is inactive.
    ///      Throws if depositing within privileged window (one hour prior to epoch flip).
    function depositManaged(address _ve, uint256 _tokenId, uint256 _mTokenId) external;

    /// @notice Called by users to withdraw from a managed NFT.
    ///         Cannot do it in the same epoch that you deposited into a managed NFT.
    ///         Can vote or deposit into a managed NFT again after withdrawing.
    ///         Note that the NFT withdrawn is re-locked to the maximum lock time.
    /// @param _ve          Address of ve token.
    /// @param _tokenId     Id of veNFT you are withdrawing from.
    function withdrawManaged(address _ve, uint256 _tokenId) external;

    /// @notice Claim bribes for a given NFT.
    /// @dev Utility to help batch bribe claims.
    /// @param _bribes  Array of BribeVotingReward contracts to collect from.
    /// @param _tokens  Array of tokens that are used as bribes.
    /// @param _ve      Address of ve token.
    /// @param _tokenId Id of veNFT that you wish to claim bribes for.
    function claimBribes(address[] memory _bribes, address[][] memory _tokens, address _ve, uint256 _tokenId)
        external;

    /// @notice Claim fees for a given NFT.
    /// @dev Utility to help batch fee claims.
    /// @param _fees    Array of FeesVotingReward contracts to collect from.
    /// @param _tokens  Array of tokens that are used as fees.
    /// @param _ve      Address of ve token.
    /// @param _tokenId Id of veNFT that you wish to claim fees for.
    function claimFees(address[] memory _fees, address[][] memory _tokens, address _ve, uint256 _tokenId) external;

    /// @notice Set maximum number of gauges that can be voted for.
    /// @dev Throws if not called by governor.
    ///      Throws if _maxVotingNum is too low.
    ///      Throws if the values are the same.
    /// @param _maxVotingNum .
    function setMaxVotingNum(uint256 _maxVotingNum) external;

    /// @notice Whitelist (or unwhitelist) token id for voting in last hour prior to epoch flip.
    /// @dev Throws if not called by governor.
    ///      Throws if already whitelisted.
    /// @param _ve      Address of ve token.
    /// @param _tokenId Id of veNFT.
    /// @param _bool    Whitelisted status.
    function whitelistNFT(address _ve, uint256 _tokenId, bool _bool) external;

    /// @notice Whitelist (or unwhitelist) token for use in bribes.
    /// @dev Throws if not called by governor.
    /// @param _token .
    /// @param _bool .
    function whitelistToken(address _token, bool _bool) external;

    /// @notice Ban voting for a pool
    /// @dev Throws if pool does not have associated voting rewards deployed
    ///      Throws if voting is already banned for this pool
    /// @param _poolId .
    function banVote(uint160 _poolId) external;

    /// @notice Reauthorize voting for a pool
    /// @dev Throws if pool does not have associated voting rewards deployed
    ///      Throws if voting is already authorized for this pool
    /// @param _poolId .
    function reauthorizeVote(uint160 _poolId) external;

    /// @notice Create voting rewards for a pool (unpermissioned).
    /// @dev Pool needs to be registered in governance registry.
    /// @param _poolId .
    function createVotingRewards(uint160 _poolId) external returns (address fees, address bribe);

    /// @notice Set the governance registry
    function setGovernanceRegistry(address _governanceRegistry) external;
}
