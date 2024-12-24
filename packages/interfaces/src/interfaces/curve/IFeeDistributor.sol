// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IFeeDistributor {
    event ApplyAdmin(address admin);
    event CheckpointToken(uint256 time, uint256 tokens);
    event Claimed(address indexed recipient, uint256 amount, uint256 claim_epoch, uint256 max_epoch);
    event CommitAdmin(address admin);
    event ToggleAllowCheckpointToken(bool toggle_flag);

    function apply_admin() external;
    function burn(address _coin) external returns (bool);
    function checkpoint_token() external;
    function checkpoint_total_supply() external;
    function claim() external returns (uint256);
    function claim(address _addr) external returns (uint256);
    function claim_many(address[20] calldata _receivers) external returns (bool);
    function commit_admin(address _addr) external;
    function kill_me() external;
    function recover_balance(address _coin) external returns (bool);
    function toggle_allow_checkpoint_token() external;
    function admin() external view returns (address);
    function can_checkpoint_token() external view returns (bool);
    function emergency_return() external view returns (address);
    function future_admin() external view returns (address);
    function is_killed() external view returns (bool);
    function last_token_time() external view returns (uint256);
    function start_time() external view returns (uint256);
    function time_cursor() external view returns (uint256);
    function time_cursor_of(address arg0) external view returns (uint256);
    function token() external view returns (address);
    function token_last_balance() external view returns (uint256);
    function tokens_per_week(uint256 arg0) external view returns (uint256);
    function total_received() external view returns (uint256);
    function user_epoch_of(address arg0) external view returns (uint256);
    function ve_for_at(address _user, uint256 _timestamp) external view returns (uint256);
    function ve_supply(uint256 arg0) external view returns (uint256);
    function voting_escrow() external view returns (address);
}
