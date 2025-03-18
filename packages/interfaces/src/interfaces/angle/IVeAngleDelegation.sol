// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IGaugeVoting {
    struct DelegateCheckpoint {
        uint128 normalizedBias;
        uint128 normalizedSlope;
        uint128 timestamp;
    }

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousVotes, uint256 newVotes);
    event EIP712DomainChanged();

    function delegate(address delegatee) external;
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;
    function writeNewCheckpointForExpiredDelegations(address delegateAddress) external;
    function CLOCK_MODE() external pure returns (string memory);
    function $delegateCheckpoints(address delegate, uint256)
        external
        view
        returns (uint128 normalizedBias, uint128 normalizedSlope, uint128 timestamp);
    function $delegations(address delegator)
        external
        view
        returns (address delegate, uint48 firstDelegationTimestamp, uint48 expiry, uint96 bias, uint64 slope);
    function $expiredDelegations(address delegate, uint256 week) external view returns (uint96 bias, uint64 slope);
    function $nonces(address signer) external view returns (uint256 nonce);
    function DELEGATION_TYPEHASH() external view returns (bytes32);
    function MAX_LOCK_DURATION() external view returns (uint256);
    function VE_ANGLE() external view returns (address);
    function VOTE_WEIGHT_MULTIPLIER() external view returns (uint256);
    function WEEK() external view returns (uint256);
    function calculateExpiredDelegations(address delegateAddress)
        external
        view
        returns (DelegateCheckpoint memory calculatedCheckpoint);
    function clock() external view returns (uint48);
    function delegates(address delegator) external view returns (address delegateAddress);
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
    function getCheckpoint(address delegateAddress, uint32 index) external view returns (DelegateCheckpoint memory);
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256 pastTotalSupply);
    function getPastVotes(address voter, uint256 timepoint) external view returns (uint256 pastVotingWeight);
    function getVotes(address voter) external view returns (uint256 votingWeight);
    function getVotes(address voter, uint256 timepoint) external view returns (uint256);
}
