// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IVECake {
    event DelegateFromCakePool(address indexed user, address indexed delegator, uint256 amount, uint256 endTime);
    event Deposit(address indexed locker, uint256 value, uint256 indexed lockTime, uint256 lockType, uint256 timestamp);
    event EarlyWithdraw(address indexed locker, address indexed to, uint256 value, uint256 penalty, uint256 timestamp);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event InjectToDelegator(address indexed user, address indexed delegator, uint256 amount);
    event MigrateFromCakePool(address indexed user, address indexed proxy, uint256 amount, uint256 endTime);
    event MigrationConvertToDelegation(
        address indexed user, address indexed delegator, uint256 amount, uint256 endTime
    );
    event NewFarmBooster(address indexed farmBooster);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Redistribute(address indexed caller, address destination, uint256 amount);
    event SetBreaker(uint256 previousBreaker, uint256 breaker);
    event SetEarlyWithdrawConfig(
        address indexed caller,
        uint64 oldEarlyWithdrawFeeBps,
        uint64 newEarlyWithdrawFeeBps,
        uint64 oldRedistributeBps,
        uint64 newRedistribiteBps,
        address oldTreasuryAddr,
        address newTreasuryAddr,
        address oldRedistributeAddr,
        address newRedistributeAddr
    );
    event SetEarlyWithdrawSwitch(address indexed user, bool newValue);
    event SetEmergencyWithdrawSwitch(address indexed user, bool newValue);
    event SetLimitTimeOfConvert(address indexed user, uint256 newValue);
    event SetNoPenaltyForEarlyWithdraw(address indexed owner, address indexed user, bool indexed newValue);
    event SetWhitelistedCaller(address indexed caller, address indexed addr, bool ok);
    event SetWhitelistedRedistributors(address indexed caller, address indexed addr, bool ok);
    event Supply(uint256 previousSupply, uint256 supply);
    event UpdateDelegator(address indexed delegator, bool isDelegator, uint40 limitTimestampForEarlyWithdraw);
    event WithdrawAll(address indexed locker, address indexed to, uint256 value, uint256 timestamp);

    function checkpoint() external;
    function createLock(uint256 _amount, uint256 _unlockTime) external;
    function createLockForProxy(uint256 _amount, uint256 _unlockTime) external;
    function delegateFromCakePool(address _delegator) external;
    function deposit(address _user, uint256 _amount, uint256 _lockDuration) external;
    function depositFor(address _for, uint256 _amount) external;
    function earlyWithdraw(address _to, uint256 _amount) external;
    function emergencyWithdraw() external;
    function increaseLockAmount(uint256 _amount) external;
    function increaseUnlockTime(uint256 _newUnlockTime) external;
    function initializeCakePoolMigration() external;
    function injectToDelegator(address _delegator, uint256 _amount) external;
    function migrateFromCakePool() external;
    function migrationConvertToDelegation(address _delegator) external;
    function redistribute() external;
    function renounceOwnership() external;
    function setBreaker(uint256 _breaker) external;
    function setEarlyWithdrawConfig(
        uint64 _newEarlyWithdrawBpsPerWeek,
        uint64 _newRedistributeBps,
        address _newTreasuryAddr,
        address _newRedistributeAddr
    ) external;
    function setEarlyWithdrawSwitch(bool _earlyWithdrawSwitch) external;
    function setEmergencyWithdrawSwitch(bool _emergencyWithdrawSwitch) external;
    function setFarmBooster(address _farmBooster) external;
    function setLimitTimeOfConvert(uint256 _limitTime) external;
    function setNoPenaltyForEarlyWithdraw(address _user, bool _status) external;
    function setWhitelistedCallers(address[] calldata callers, bool ok) external;
    function setWhitelistedRedistributors(address[] calldata callers, bool ok) external;
    function transferOwnership(address newOwner) external;
    function updateDelegator(address _delegator, bool _isDelegator, uint40 _limitTimestampForEarlyWithdraw) external;
    function withdraw(address _user) external;
    function withdrawAll(address _to) external;
    function ACTION_CREATE_LOCK() external view returns (uint256);
    function ACTION_DEPOSIT_FOR() external view returns (uint256);
    function ACTION_INCREASE_LOCK_AMOUNT() external view returns (uint256);
    function ACTION_INCREASE_UNLOCK_TIME() external view returns (uint256);
    function CakePool() external view returns (address);
    function DELEGATION_FROM_CAKE_POOL_FLAG() external view returns (uint16);
    function DELEGATOR_FLAG() external view returns (uint8);
    function FarmBooster() external view returns (address);
    function MAX_LOCK() external view returns (uint256);
    function MIGRATION_FROM_CAKE_POOL_FLAG() external view returns (uint16);
    function MULTIPLIER() external view returns (uint256);
    function NOT_DELEGATOR_FLAG() external view returns (uint8);
    function NOT_WITHDRAW_FLAG() external view returns (uint16);
    function ProxyForCakePoolFactory() external view returns (address);
    function WEEK() external view returns (uint256);
    function WITHDREW_FLAG() external view returns (uint16);
    function accumRedistribute() external view returns (uint256);
    function balanceOf(address _user) external view returns (uint256);
    function balanceOfAt(address _user, uint256 _blockNumber) external view returns (uint256);
    function balanceOfAtForProxy(address _user, uint256 _blockNumber) external view returns (uint256);
    function balanceOfAtTime(address _user, uint256 _timestamp) external view returns (uint256);
    function balanceOfAtUser(address _user, uint256 _blockNumber) external view returns (uint256);
    function balanceOfForProxy(address _user) external view returns (uint256);
    function balanceOfUser(address _user) external view returns (uint256);
    function breaker() external view returns (uint256);
    function decimals() external view returns (uint8);
    function delegator(address)
        external
        view
        returns (
            uint104 delegatedCakeAmount,
            uint104 notInjectedCakeAmount,
            uint40 limitTimestampForEarlyWithdraw,
            uint8 isDelegator
        );
    function earlyWithdrawBpsPerWeek() external view returns (uint64);
    function earlyWithdrawSwitch() external view returns (bool);
    function emergencyWithdrawSwitch() external view returns (bool);
    function epoch() external view returns (uint256);
    function everEmergencyWithdraw(address) external view returns (bool);
    function getUserInfo(address _user)
        external
        view
        returns (
            int128 amount,
            uint256 end,
            address cakePoolProxy,
            uint128 cakeAmount,
            uint48 lockEndTime,
            uint48 migrationTime,
            uint16 cakePoolType,
            uint16 withdrawFlag
        );
    function initialization() external view returns (bool);
    function isCakePoolProxy(address) external view returns (bool);
    function limitTimeOfConvert() external view returns (uint256);
    function locks(address) external view returns (int128 amount, uint256 end);
    function name() external view returns (string memory);
    function noPenaltyForEarlyWithdraw(address) external view returns (bool);
    function owner() external view returns (address);
    function pointHistory(uint256)
        external
        view
        returns (int128 bias, int128 slope, uint256 timestamp, uint256 blockNumber);
    function redistributeAddr() external view returns (address);
    function redistributeBps() external view returns (uint64);
    function slopeChanges(uint256) external view returns (int128);
    function supply() external view returns (uint256);
    function symbol() external view returns (string memory);
    function token() external view returns (address);
    function totalSupply() external view returns (uint256);
    function totalSupplyAt(uint256 _blockNumber) external view returns (uint256);
    function totalSupplyAtTime(uint256 _timestamp) external view returns (uint256);
    function treasuryAddr() external view returns (address);
    function userInfo(address)
        external
        view
        returns (
            address cakePoolProxy,
            uint128 cakeAmount,
            uint48 lockEndTime,
            uint48 migrationTime,
            uint16 cakePoolType,
            uint16 withdrawFlag
        );
    function userPointEpoch(address) external view returns (uint256);
    function userPointHistory(address, uint256)
        external
        view
        returns (int128 bias, int128 slope, uint256 timestamp, uint256 blockNumber);
    function whitelistedCallers(address) external view returns (bool);
    function whitelistedRedistributors(address) external view returns (bool);
}
