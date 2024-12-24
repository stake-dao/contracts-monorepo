// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IGaugeController {
    event AddType(string name, int128 type_id);
    event ApplyOwnership(address admin);
    event CommitOwnership(address admin);
    event KilledGauge(address addr);
    event NewGauge(address addr, int128 gauge_type, uint256 weight);
    event NewGaugeWeight(address gauge_address, uint256 time, uint256 weight, uint256 total_weight);
    event NewTypeWeight(int128 type_id, uint256 time, uint256 weight, uint256 total_weight);
    event VoteForGauge(uint256 time, address user, address gauge_addr, uint256 weight);

    function accept_transfer_ownership() external;
    function add_gauge(address addr, int128 gauge_type) external;
    function add_gauge(address addr, int128 gauge_type, uint256 weight) external;
    function add_type(string calldata _name) external;
    function add_type(string calldata _name, uint256 weight) external;
    function change_gauge_weight(address addr, uint256 weight) external;
    function change_type_weight(int128 type_id, uint256 weight) external;
    function checkpoint() external;
    function checkpoint_gauge(address addr) external;
    function commit_transfer_ownership(address addr) external;
    function gauge_relative_weight_write(address addr) external returns (uint256);
    function gauge_relative_weight_write(address addr, uint256 time) external returns (uint256);
    function vote_for_gauge_weights(address _gauge_addr, uint256 _user_weight) external;
    function admin() external view returns (address);
    function future_admin() external view returns (address);
    function gauge_relative_weight(address addr) external view returns (uint256);
    function gauge_relative_weight(address addr, uint256 time) external view returns (uint256);
    function gauge_type_names(int128 arg0) external view returns (string memory);
    function gauge_types(address _addr) external view returns (int128);
    function gauges(uint256 arg0) external view returns (address);
    function get_gauge_weight(address addr) external view returns (uint256);
    function get_total_weight() external view returns (uint256);
    function get_type_weight(int128 type_id) external view returns (uint256);
    function get_weights_sum_per_type(int128 type_id) external view returns (uint256);
    function last_user_vote(address arg0, address arg1) external view returns (uint256);
    function n_gauge_types() external view returns (int128);
    function n_gauges() external view returns (int128);
    function points_sum(int128 arg0, uint256 arg1) external view returns (uint256 bias, uint256 slope);
    function points_total(uint256 arg0) external view returns (uint256);
    function points_type_weight(int128 arg0, uint256 arg1) external view returns (uint256);
    function points_weight(address arg0, uint256 arg1) external view returns (uint256 bias, uint256 slope);
    function time_sum(uint256 arg0) external view returns (uint256);
    function time_total() external view returns (uint256);
    function time_type_weight(uint256 arg0) external view returns (uint256);
    function time_weight(address arg0) external view returns (uint256);
    function token() external view returns (address);
    function vote_user_power(address arg0) external view returns (uint256);
    function vote_user_slopes(address arg0, address arg1)
        external
        view
        returns (uint256 slope, uint256 power, uint256 end);
    function voting_escrow() external view returns (address);
}
