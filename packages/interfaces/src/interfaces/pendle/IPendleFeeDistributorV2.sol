// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IPendleFeeDistributorV2 {
    struct UpdateProtocolStruct {
        address user;
        bytes32[] proof;
        address[] pools;
        uint256[] topUps;
    }

    event AdminChanged(address previousAdmin, address newAdmin);
    event BeaconUpgraded(address indexed beacon);
    event Claimed(address indexed user, uint256 amountOut);
    event Initialized(uint8 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SetMerkleRootAndFund(bytes32 indexed merkleRoot, uint256 amountFunded);
    event UpdateProtocolClaimable(address indexed user, uint256 sumTopUp);
    event Upgraded(address indexed implementation);

    function claimOwnership() external;
    function claimProtocol(address receiver, address[] calldata pools)
        external
        returns (uint256 totalAmountOut, uint256[] memory amountsOut);
    function claimRetail(address receiver, uint256 totalAccrued, bytes32[] calldata proof)
        external
        returns (uint256 amountOut);
    function initialize() external;
    function transferOwnership(address newOwner, bool direct, bool renounce) external;
    function updateProtocolClaimable(UpdateProtocolStruct calldata ele) external;
    function updateProtocolClaimables(UpdateProtocolStruct[] calldata arr) external;
    function upgradeTo(address newImplementation) external;
    function setMerkleRootAndFund(bytes32 newMerkleRoot, uint256 amountToFund) external payable;
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
    function claimed(address) external view returns (uint256);
    function getProtocolClaimables(address user, address[] calldata pools)
        external
        view
        returns (uint256[] memory claimables);
    function getProtocolTotalAccrued(address user) external view returns (uint256);
    function merkleRoot() external view returns (bytes32);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function proxiableUUID() external view returns (bytes32);
}
