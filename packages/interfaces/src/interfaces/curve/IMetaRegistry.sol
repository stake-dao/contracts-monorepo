// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

interface IMetaRegistry {
    function find_pool_for_coins(address _from, address _to, uint256 i) external view returns (address);
    function get_admin_balances(address _pool) external view returns (uint256[8] memory);
    function get_balances(address _pool) external view returns (uint256[8] memory);
    function get_base_pool(address _pool) external view returns (address);
    function get_coins(address _pool) external view returns (address[8] memory);
    function get_coin_indices(address _pool, address _from, address _to) external view returns (int128, int128, bool);
    function get_decimals(address _pool) external view returns (uint256[8] memory);
    function get_fees(address _pool) external view returns (uint256[10] memory);
    function get_gauges(address _pool) external view returns (address[10] memory, int128[10] memory);
    function get_lp_token(address _pool) external view returns (address);
    function get_n_coins(address _pool) external view returns (uint256);
    function get_n_underlying_coins(address _pool) external view returns (uint256);
    function get_pool_asset_type(address _pool) external view returns (uint256);
    function get_pool_from_lp_token(address _lp_token) external view returns (address);
    function get_pool_name(address _pool) external view returns (string[64] memory);
    function get_pool_params(address _pool) external view returns (uint256[20] memory);
    function get_underlying_balances(address _pool) external view returns (uint256[8] memory);
    function get_underlying_coins(address _pool) external view returns (address[8] memory);
    function get_underlying_decimals(address _pool) external view returns (uint256[8] memory);
    function is_meta(address _pool) external view returns (bool);
    function is_registered(address _pool) external view returns (bool);
    function pool_count() external view returns (uint256);
    function pool_list(uint256 _index) external view returns (address);
    function get_virtual_price_from_lp_token(address _addr) external view returns (uint256);
    function base_registry() external view returns (address);
}
