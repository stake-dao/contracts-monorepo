// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IFeeDistributor {
    event OnlyCallerOptIn(address user, bool enabled);
    event TokenCheckpointed(address token, uint256 amount, uint256 lastCheckpointTimestamp);
    event TokensClaimed(address user, address token, uint256 amount, uint256 userTokenTimeCursor);

    function checkpoint() external;
    function checkpointToken(address token) external;
    function checkpointTokens(address[] calldata tokens) external;
    function checkpointUser(address user) external;
    function claimToken(address user, address token) external returns (uint256);
    function claimTokens(address user, address[] calldata tokens) external returns (uint256[] memory);
    function depositToken(address token, uint256 amount) external;
    function depositTokens(address[] calldata tokens, uint256[] calldata amounts) external;
    function setOnlyCallerCheck(bool enabled) external;
    function setOnlyCallerCheckWithSignature(address user, bool enabled, bytes calldata signature) external;
    function getDomainSeparator() external view returns (bytes32);
    function getNextNonce(address account) external view returns (uint256);
    function getTimeCursor() external view returns (uint256);
    function getTokenLastBalance(address token) external view returns (uint256);
    function getTokenTimeCursor(address token) external view returns (uint256);
    function getTokensDistributedInWeek(address token, uint256 timestamp) external view returns (uint256);
    function getTotalSupplyAtTimestamp(uint256 timestamp) external view returns (uint256);
    function getUserBalanceAtTimestamp(address user, uint256 timestamp) external view returns (uint256);
    function getUserTimeCursor(address user) external view returns (uint256);
    function getUserTokenTimeCursor(address user, address token) external view returns (uint256);
    function getVotingEscrow() external view returns (address);
    function isOnlyCallerEnabled(address user) external view returns (bool);
}
