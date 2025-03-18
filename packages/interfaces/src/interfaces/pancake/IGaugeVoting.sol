// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IGaugeVoting {
    event AddType(string name, uint256 type_id);
    event AdminAllocationChanged(address indexed sender, uint256 allocation);
    event AdminOnlyPeriodUpdated(address indexed sender, uint256 period);
    event GaugeKilled(address indexed sender, address indexed gauage_addr, uint256 chainId, bytes32 hash);
    event GaugeUnKilled(address indexed sender, address indexed gauage_addr, uint256 chainId, bytes32 hash);
    event NewGauge(
        bytes32 hash,
        uint256 gauge_type,
        uint256 weight,
        uint256 pid,
        address masterChef,
        uint256 chainId,
        uint256 boostMultiplier,
        uint256 maxVoteCap
    );
    event NewGaugeWeight(bytes32 hash, uint256 time, uint256 weight, uint256 total_weight);
    event NewTypeWeight(uint256 type_id, uint256 time, uint256 weight, uint256 total_weight);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);
    event UpdateGaugeInfo(
        bytes32 hash, uint256 pid, address masterChef, uint256 chainId, uint256 boostMultiplier, uint256 maxVoteCap
    );
    event VoteForGauge(uint256 time, address user, bytes32 hash, uint256 weight);
    event VoteForGaugeFromAdmin(uint256 time, address user, bytes32 hash, uint256 weight);
    event WeightVoteDelayChanged(address indexed sender, uint256 delay);

    function addGauge(
        address gauge_addr,
        uint256 gauge_type,
        uint256 _weight,
        uint256 _pid,
        address _masterChef,
        uint256 _chainId,
        uint256 _boostMultiplier,
        uint256 _maxVoteCap
    ) external;
    function addType(string calldata _name, uint256 _weight) external;
    function changeAdminAllocation(uint256 _numerator) external;
    function changeGaugeWeight(address gauge_addr, uint256 weight, uint256 _chainId) external;
    function changeTypeWeight(uint256 type_id, uint256 weight) external;
    function changeWeightVoteDelay(uint256 _delay) external;
    function checkpoint() external;
    function checkpointGauge(address gauge_addr, uint256 _chainId) external;
    function gaugeRelativeWeight_write(address gauge_addr, uint256 time, uint256 _chainId) external returns (uint256);
    function killGauge(address _gauge_addr, uint256 _chainId) external;
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external;
    function unkillGauge(address _gauge_addr, uint256 _chainId) external;
    function updateAdminOnlyPeriod(uint256 _newAdminOnlyPeriod) external;
    function updateGaugeInfo(
        address gauge_addr,
        uint256 _pid,
        address _masterChef,
        uint256 _chainId,
        uint256 _boostMultiplier,
        uint256 _maxVoteCap
    ) external;
    function voteForGaugeWeights(
        address _gauge_addr,
        uint256 _user_weight,
        uint256 _chainId,
        bool _skipNative,
        bool _skipProxy
    ) external;
    function voteForGaugeWeightsBulk(
        address[] calldata _gauge_addrs,
        uint256[] calldata _user_weights,
        uint256[] calldata _chainIds,
        bool _skipNative,
        bool _skipProxy
    ) external;
    function voteFromAdmin(address _gauge_addr, uint256 _admin_weight, uint256 _end, uint256 _chainId) external;
    function voteFromAdminBulk(
        address[] calldata _gauge_addrs,
        uint256[] calldata _admin_weights,
        uint256[] calldata _ends,
        uint256[] calldata _chainIds
    ) external;
    function ADMIN_VOTE_PERIOD() external view returns (uint256);
    function WEIGHT_VOTE_DELAY() external view returns (uint256);
    function adminAllocation() external view returns (uint256);
    function adminSlopes(uint256) external view returns (uint256);
    function gaugeChangesWeight(bytes32, uint256) external view returns (uint256);
    function gaugeCount() external view returns (uint256);
    function gaugeIndex_(bytes32) external view returns (uint256);
    function gaugeIsKilled_(bytes32) external view returns (bool);
    function gaugeLastScheduled(bytes32) external view returns (uint256);
    function gaugePointsTotal(uint256) external view returns (uint256);
    function gaugePointsWeight(bytes32, uint256) external view returns (uint256 bias, uint256 slope);
    function gaugeRelativeWeight(address gauge_addr, uint256 time, uint256 _chainId) external view returns (uint256);
    function gaugeTypeChangesSum(uint256, uint256) external view returns (uint256);
    function gaugeTypeLastScheduled(uint256) external view returns (uint256);
    function gaugeTypeNames(uint256) external view returns (string memory);
    function gaugeTypePointsSum(uint256, uint256) external view returns (uint256 bias, uint256 slope);
    function gaugeTypePointsWeight(uint256, uint256) external view returns (uint256);
    function gaugeTypeSumLastScheduled(uint256) external view returns (uint256);
    function gaugeTypes() external view returns (uint256);
    function gaugeTypes_(bytes32) external view returns (uint256);
    function gauges(uint256)
        external
        view
        returns (
            uint256 pid,
            address masterChef,
            uint256 chainId,
            address pairAddress,
            uint256 boostMultiplier,
            uint256 maxVoteCap
        );
    function getGaugeWeight(address gauge_addr, uint256 _chainId, bool inCap) external view returns (uint256);
    function getTotalWeight(bool inCap) external view returns (uint256);
    function getTypeAndChainIdWeightCapped(uint256 _typeId, uint256 _chainId) external view returns (uint256);
    function getWeightsSumPerType(uint256 _typeId) external view returns (uint256);
    function lastUserVote(address, bytes32) external view returns (uint256);
    function owner() external view returns (address);
    function paused() external view returns (bool);
    function totalLastScheduled() external view returns (uint256);
    function voteUserPower(address) external view returns (uint256);
    function voteUserSlopes(address, bytes32) external view returns (uint256 slope, uint256 power, uint256 end);
    function votingEscrow() external view returns (address);
}
