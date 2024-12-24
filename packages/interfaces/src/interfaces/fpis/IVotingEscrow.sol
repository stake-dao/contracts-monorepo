// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IGaugeVoting {
    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
        uint256 fpis_amt;
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    event AcceptOwnership(address admin);
    event AppIncreaseAmountForsToggled(bool appIncreaseAmountForsEnabled);
    event Deposit(
        address indexed provider,
        address indexed payer_addr,
        uint256 value,
        uint256 indexed locktime,
        int128 _type,
        uint256 ts
    );
    event EmergencyUnlockToggled(bool emergencyUnlockActive);
    event HistoricalProxyToggled(address proxy_address, bool enabled);
    event LendingProxySet(address proxy_address);
    event NominateOwnership(address admin);
    event ProxyAdd(address indexed staker_addr, address indexed proxy_addr, uint256 add_amt);
    event ProxyAddsToggled(bool proxyAddsEnabled);
    event ProxySlash(address indexed staker_addr, address indexed proxy_addr, uint256 slash_amt);
    event ProxySlashesToggled(bool proxySlashesEnabled);
    event ProxyTransferFromsToggled(bool appTransferFromsEnabled);
    event ProxyTransferTosToggled(bool appTransferTosEnabled);
    event SmartWalletCheckerApplied(address smart_wallet_checker);
    event SmartWalletCheckerComitted(address future_smart_wallet_checker);
    event StakerProxySet(address proxy_address);
    event Supply(uint256 prevSupply, uint256 supply);
    event TransferFromApp(address indexed app_addr, address indexed staker_addr, uint256 transfer_amt);
    event TransferToApp(address indexed staker_addr, address indexed app_addr, uint256 transfer_amt);
    event Withdraw(address indexed provider, address indexed to_addr, uint256 value, uint256 ts);

    function accept_transfer_ownership() external;
    function adminSetProxy(address _proxy) external;
    function adminToggleHistoricalProxy(address _proxy) external;
    function apply_smart_wallet_checker() external;
    function checkpoint() external;
    function checkpoint_user(address _staker_addr) external;
    function commit_smart_wallet_checker(address addr) external;
    function create_lock(uint256 _value, uint256 _unlock_time) external;
    function increase_amount(uint256 _value) external;
    function increase_amount_for(address _staker_addr, uint256 _value) external;
    function increase_unlock_time(uint256 _unlock_time) external;
    function nominate_ownership(address addr) external;
    function proxy_add(address _staker_addr, uint256 _add_amt) external;
    function proxy_slash(address _staker_addr, uint256 _slash_amt) external;
    function recoverERC20(address token_addr, uint256 amount) external;
    function stakerSetProxy(address _proxy) external;
    function toggleAppIncreaseAmountFors() external;
    function toggleEmergencyUnlock() external;
    function toggleProxyAdds() external;
    function toggleProxySlashes() external;
    function toggleTransferFromApp() external;
    function toggleTransferToApp() external;
    function transfer_from_app(address _staker_addr, address _app_addr, int128 _transfer_amt) external;
    function transfer_to_app(address _staker_addr, address _app_addr, int128 _transfer_amt) external;
    function withdraw() external;
    function admin() external view returns (address);
    function appIncreaseAmountForsEnabled() external view returns (bool);
    function appTransferFromsEnabled() external view returns (bool);
    function appTransferTosEnabled() external view returns (bool);
    function balanceOf(address addr) external view returns (uint256);
    function balanceOf(address addr, uint256 _t) external view returns (uint256);
    function balanceOfAt(address addr, uint256 _block) external view returns (uint256);
    function curr_period_start() external view returns (uint256);
    function current_proxy() external view returns (address);
    function decimals() external view returns (uint256);
    function emergencyUnlockActive() external view returns (bool);
    function epoch() external view returns (uint256);
    function future_admin() external view returns (address);
    function future_smart_wallet_checker() external view returns (address);
    function get_last_point() external view returns (Point memory);
    function get_last_user_bias(address addr) external view returns (int128);
    function get_last_user_point(address addr) external view returns (Point memory);
    function get_last_user_slope(address addr) external view returns (int128);
    function historical_proxies(address arg0) external view returns (bool);
    function locked(address arg0) external view returns (LockedBalance memory);
    function locked__amount(address _addr) external view returns (int128);
    function locked__end(address _addr) external view returns (uint256);
    function name() external view returns (string memory);
    function next_period_start() external view returns (uint256);
    function point_history(uint256 arg0) external view returns (Point memory);
    function proxyAddsEnabled() external view returns (bool);
    function proxySlashesEnabled() external view returns (bool);
    function slope_changes(uint256 arg0) external view returns (int128);
    function smart_wallet_checker() external view returns (address);
    function staker_whitelisted_proxy(address arg0) external view returns (address);
    function supply() external view returns (uint256);
    function symbol() external view returns (string memory);
    function token() external view returns (address);
    function totalFPISSupply() external view returns (uint256);
    function totalFPISSupplyAt(uint256 _block) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalSupply(uint256 t) external view returns (uint256);
    function totalSupplyAt(uint256 _block) external view returns (uint256);
    function user_point_epoch(address arg0) external view returns (uint256);
    function user_point_history(address arg0, uint256 arg1) external view returns (Point memory);
    function user_point_history__ts(address _addr, uint256 _idx) external view returns (uint256);
    function user_proxy_balance(address arg0) external view returns (uint256);
    function version() external view returns (string memory);
}
