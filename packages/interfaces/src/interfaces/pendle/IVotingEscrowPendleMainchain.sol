// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IVotingEscrowPendleMainchain {
    struct VeBalance {
        uint128 bias;
        uint128 slope;
    }

    struct Checkpoint {
        uint128 timestamp;
        VeBalance value;
    }

    event BroadcastTotalSupply(VeBalance newTotalSupply, uint256[] chainIds);
    event BroadcastUserPosition(address indexed user, uint256[] chainIds);
    event Initialized(uint8 version);
    event NewLockPosition(address indexed user, uint128 amount, uint128 expiry);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Withdraw(address indexed user, uint128 amount);

    function claimOwnership() external;
    function increaseLockPosition(uint128 additionalAmountToLock, uint128 newExpiry)
        external
        returns (uint128 newVeBalance);
    function setApproxDstExecutionGas(uint256 gas) external;
    function totalSupplyAndBalanceCurrent(address user) external returns (uint128, uint128);
    function totalSupplyCurrent() external returns (uint128);
    function transferOwnership(address newOwner, bool direct, bool renounce) external;
    function withdraw() external returns (uint128 amount);
    function addDestinationContract(address _address, uint256 _chainId) external payable;
    function broadcastTotalSupply(uint256[] calldata chainIds) external payable;
    function broadcastUserPosition(address user, uint256[] calldata chainIds) external payable;
    function increaseLockPositionAndBroadcast(
        uint128 additionalAmountToLock,
        uint128 newExpiry,
        uint256[] calldata chainIds
    ) external payable returns (uint128 newVeBalance);
    function MAX_LOCK_TIME() external view returns (uint128);
    function MIN_LOCK_TIME() external view returns (uint128);
    function WEEK() external view returns (uint128);
    function approxDstExecutionGas() external view returns (uint256);
    function balanceOf(address user) external view returns (uint128);
    function getAllDestinationContracts() external view returns (uint256[] memory chainIds, address[] memory addrs);
    function getBroadcastPositionFee(uint256[] calldata chainIds) external view returns (uint256 fee);
    function getBroadcastSupplyFee(uint256[] calldata chainIds) external view returns (uint256 fee);
    function getUserHistoryAt(address user, uint256 index) external view returns (Checkpoint memory);
    function getUserHistoryLength(address user) external view returns (uint256);
    function lastSlopeChangeAppliedAt() external view returns (uint128);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function pendle() external view returns (address);
    function pendleMsgSendEndpoint() external view returns (address);
    function positionData(address) external view returns (uint128 amount, uint128 expiry);
    function slopeChanges(uint128) external view returns (uint128);
    function totalSupplyAt(uint128) external view returns (uint128);
    function totalSupplyStored() external view returns (uint128);
}
