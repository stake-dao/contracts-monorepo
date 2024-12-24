// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IYFIRewardPool {
    event AllowedToRelock(address indexed user, address indexed relocker, bool allowed);
    event CheckpointToken(uint256 time, uint256 tokens);
    event Claimed(address indexed recipient, uint256 amount, uint256 week_cursor, uint256 max_epoch);
    event Initialized(address veyfi, uint256 start_time);
    event RewardReceived(address indexed sender, uint256 amount);

    function burn() external returns (bool);
    function burn(uint256 amount) external returns (bool);
    function checkpoint_token() external;
    function checkpoint_total_supply() external;
    function claim() external returns (uint256);
    function claim(address user) external returns (uint256);
    function claim(address user, bool relock) external returns (uint256);
    function toggle_allowed_to_relock(address user) external returns (bool);
    function allowed_to_relock(address arg0, address arg1) external view returns (bool);
    function last_token_time() external view returns (uint256);
    function start_time() external view returns (uint256);
    function time_cursor() external view returns (uint256);
    function time_cursor_of(address arg0) external view returns (uint256);
    function token() external view returns (address);
    function token_last_balance() external view returns (uint256);
    function tokens_per_week(uint256 arg0) external view returns (uint256);
    function ve_supply(uint256 arg0) external view returns (uint256);
    function veyfi() external view returns (address);
}
