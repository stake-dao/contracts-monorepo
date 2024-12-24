// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IVotingEscrow {
    event ApplyOwnership(address admin);
    event CommitOwnership(address admin);
    event Deposit(address indexed provider, uint256 value, uint256 indexed locktime, int128 _type, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);
    event Withdraw(address indexed provider, uint256 value, uint256 ts);

    function accept_transfer_ownership() external;
    function apply_smart_wallet_checker() external;
    function apply_transfer_ownership() external;
    function checkpoint() external;
    function commit_smart_wallet_checker(address addr) external;
    function commit_transfer_ownership(address addr) external;
    function create_lock(uint256 _value, uint256 _unlock_time) external;
    function deposit_for(address _addr, uint256 _value) external;
    function increase_amount(uint256 _value) external;
    function increase_unlock_time(uint256 _unlock_time) external;
    function initialize(
        address _admin,
        address token_addr,
        address _smart_wallet_checker,
        string calldata _name,
        string calldata _symbol
    ) external;
    function withdraw() external;
    function admin() external view returns (address);
    function balanceOf(address addr) external view returns (uint256);
    function balanceOf(address addr, uint256 _t) external view returns (uint256);
    function balanceOfAt(address addr, uint256 _block) external view returns (uint256);
    function decimals() external view returns (uint256);
    function epoch() external view returns (uint256);
    function future_admin() external view returns (address);
    function future_smart_wallet_checker() external view returns (address);
    function getPastVotes(address addr, uint256 _block) external view returns (uint256);
    function get_last_user_slope(address addr) external view returns (int128);
    function initialized() external view returns (bool);
    function locked(address arg0) external view returns (int128 amount, uint256 end);
    function locked__end(address _addr) external view returns (uint256);
    function name() external view returns (string memory);
    function point_history(uint256 arg0) external view returns (int128 bias, int128 slope, uint256 ts, uint256 blk);
    function slope_changes(uint256 arg0) external view returns (int128);
    function smart_wallet_checker() external view returns (address);
    function supply() external view returns (uint256);
    function symbol() external view returns (string memory);
    function token() external view returns (address);
    function totalSupply() external view returns (uint256);
    function totalSupply(uint256 t) external view returns (uint256);
    function totalSupplyAt(uint256 _block) external view returns (uint256);
    function user_point_epoch(address arg0) external view returns (uint256);
    function user_point_history(address arg0, uint256 arg1)
        external
        view
        returns (int128 bias, int128 slope, uint256 ts, uint256 blk);
    function user_point_history__ts(address _addr, uint256 _idx) external view returns (uint256);
}
