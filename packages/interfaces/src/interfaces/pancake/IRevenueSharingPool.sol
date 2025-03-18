// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IRevenueSharingPool {
    event CheckpointToken(uint256 _timestamp, uint256 _tokens);
    event Claimed(
        address indexed _user, address indexed _recipient, uint256 _amount, uint256 _claimEpoch, uint256 _maxEpoch
    );
    event Feed(uint256 _amount);
    event Killed();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SetCanCheckpointToken(bool _toggleFlag);
    event SetWhitelistedCheckpointCallers(address indexed _caller, address indexed _address, bool _ok);
    event UpdateRecipient(
        address _owner, address indexed _user, address indexed _oldRecipient, address indexed _newRecipient
    );

    function checkpointToken() external;
    function checkpointTotalSupply() external;
    function claim(address _user) external returns (uint256);
    function claimForUser(address _user) external returns (uint256);
    function claimMany(address[] calldata _users) external returns (bool);
    function claimTo(address _recipient) external returns (uint256);
    function feed(uint256 _amount) external returns (bool);
    function injectReward(uint256 _timestamp, uint256 _amount) external;
    function injectRewardForCurrentWeek(uint256 _amount) external;
    function kill() external;
    function renounceOwnership() external;
    function setCanCheckpointToken(bool _newCanCheckpointToken) external;
    function setRecipient(address _user, address _recipient) external;
    function setWhitelistedCheckpointCallers(address[] calldata _callers, bool _ok) external;
    function transferOwnership(address newOwner) external;
    function TOKEN_CHECKPOINT_DEADLINE() external view returns (uint256);
    function VECake() external view returns (address);
    function WEEK() external view returns (uint256);
    function balanceOfAt(address _user, uint256 _timestamp) external view returns (uint256);
    function balanceOfAtProxy(address _user, uint256 _timestamp) external view returns (uint256);
    function balanceOfAtUser(address _user, uint256 _timestamp) external view returns (uint256);
    function canCheckpointToken() external view returns (bool);
    function emergencyReturn() external view returns (address);
    function everSetRecipient(address) external view returns (bool);
    function getRecipient(address _user) external view returns (address _recipient);
    function isKilled() external view returns (bool);
    function lastTokenBalance() external view returns (uint256);
    function lastTokenTimestamp() external view returns (uint256);
    function owner() external view returns (address);
    function recipient(address) external view returns (address);
    function rewardToken() external view returns (address);
    function startWeekCursor() external view returns (uint256);
    function tokensPerWeek(uint256) external view returns (uint256);
    function totalDistributed() external view returns (uint256);
    function totalSupplyAt(uint256) external view returns (uint256);
    function userEpochOf(address) external view returns (uint256);
    function weekCursor() external view returns (uint256);
    function weekCursorOf(address) external view returns (uint256);
    function whitelistedCheckpointCallers(address) external view returns (bool);
}
