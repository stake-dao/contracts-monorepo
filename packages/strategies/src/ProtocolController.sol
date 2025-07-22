// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title ProtocolController.
/// @author Stake DAO
/// @custom:github @stake-dao
/// @custom:contact contact@stakedao.org

/// @notice ProtocolController is the central registry that facilitate the management of protocols integrations.
///         It allows the registration of vaults, management of protocol components (strategy, allocator, accountant, etc.),
///         and provides a permission system for granular access control.
///         It also supports pausing deposits for specific protocols while allowing withdrawals, and shutdown mechanisms per vault or at the protocol level.
contract ProtocolController is IProtocolController, Ownable2Step {
    /// @notice Stores the core components for each protocol integration.
    /// @dev    Each protocol (Curve, Balancer, etc.) has its own set of components.
    struct ProtocolComponents {
        address locker;
        address gateway;
        address strategy;
        address allocator;
        address accountant;
        address feeReceiver;
        address factory;
    }

    /// @notice Links a gauge to its associated vault and protocol.
    /// @dev    A gauge is the external yield source (e.g., Curve gauge) that the vault interacts with.
    struct Gauge {
        address vault;
        address asset;
        address rewardReceiver;
        bytes4 protocolId;
        bool isShutdown;
    }

    //////////////////////////////////////////////////////
    // --- STATE VARIABLES
    //////////////////////////////////////////////////////

    /// @notice Maps each gauge address to its configuration.
    mapping(address => Gauge) public gauge;

    /// @notice Authorized addresses that can register new vaults, such as factory contracts.
    mapping(address => bool) public registrar;

    /// @notice Addresses authorized to manage granular function-level permissions.
    mapping(address => bool) public permissionSetters;

    /// @notice Core components for each protocol, indexed by protocol ID.
    /// @dev    Protocol ID is typically keccak256("PROTOCOL_NAME") truncated to bytes4.
    mapping(bytes4 => ProtocolComponents) internal _protocolComponents;

    /// @notice Whitelisted allocation targets for each gauge.
    /// @dev    Strategies can only allocate funds to these pre-approved destinations (e.g., locker, sidecars).
    mapping(address => mapping(address => bool)) internal _isValidAllocationTargets;

    /// @notice Granular permission system: contract -> caller -> function -> allowed.
    /// @dev    Enables fine-grained access control for specific function calls. Main usecase is to allow router contracts
    ///         to deposit on behalf or claim on behalf of accounts.
    mapping(address => mapping(address => mapping(bytes4 => bool))) internal _permissions;

    /// @notice Per-protocol deposit pause state.
    /// @dev    When true for a protocol, deposits are paused but withdrawals remain functional.
    mapping(bytes4 => bool) public isPaused;

    //////////////////////////////////////////////////////
    // --- ERRORS & EVENTS
    //////////////////////////////////////////////////////

    /// @notice Event emitted when a protocol component is set.
    /// @param  protocolId The protocol identifier.
    /// @param  componentId The component identifier ("Strategy", "Allocator", "Accountant", "FeeReceiver", "Locker", "Gateway", "Factory").
    /// @param  component The component address.
    event ProtocolComponentSet(bytes4 indexed protocolId, string indexed componentId, address indexed component);

    /// @notice Event emitted when a vault is registered.
    /// @param  gauge The gauge address.
    /// @param  vault The vault address.
    /// @param  asset The asset address.
    /// @param  rewardReceiver The reward receiver address.
    /// @param  protocolId The protocol identifier.
    event VaultRegistered(
        address indexed gauge, address indexed vault, address indexed asset, address rewardReceiver, bytes4 protocolId
    );

    /// @notice Event emitted when a gauge is shutdown.
    /// @param  gauge The gauge address that is being shutdown.
    event GaugeShutdown(address indexed gauge);

    /// @notice Event emitted when a gauge is unshut down.
    /// @param  gauge The gauge address that is being unshut down.
    event GaugeUnshutdown(address indexed gauge);

    /// @notice Event emitted when a protocol is shutdown.
    /// @param  protocolId The protocol identifier of the protocol integration that is being shutdown.
    event ProtocolShutdown(bytes4 indexed protocolId);

    /// @notice Event emitted when a permission is set.
    /// @param  target The contract address where the permission is valid.
    /// @param  caller The caller address that is allowed to call the function.
    /// @param  selector The function selector that is being allowed or disallowed.
    /// @param  allowed Whether the caller is allowed to call the function on the contract.
    event PermissionSet(address indexed target, address indexed caller, bytes4 indexed selector, bool allowed);

    /// @notice Event emitted when a registrar is added or removed to the list of authorized registrars.
    /// @param  registrar The registrar address that is being set or unset.
    /// @param  allowed Whether the registrar is allowed to manage vault registrations and rewards tokens.
    event RegistrarPermissionSet(address indexed registrar, bool allowed);

    /// @notice Event emitted when a permission setter is set.
    /// @param  setter The permission setter address that is being set or unset and have rights to set permissions.
    /// @param  allowed Whether the permission setter is allowed to set permissions.
    event PermissionSetterSet(address indexed setter, bool allowed);

    /// @notice Event emitted when deposits are paused for a protocol.
    /// @param  protocolId The protocol identifier of the protocol integration that is being paused.
    event Paused(bytes4 indexed protocolId);

    /// @notice Event emitted when deposits are unpaused for a protocol.
    /// @param  protocolId The protocol identifier of the protocol integration that is being unpaused.
    event Unpaused(bytes4 indexed protocolId);

    /// @notice Thrown when a non-strategy calls a strategy-only function.
    error OnlyStrategy();

    /// @notice Thrown when a non-registrar calls a registrar-only function.
    error OnlyRegistrar();

    /// @notice Thrown when a zero address is used.
    error ZeroAddress();

    /// @notice Thrown when an accountant is already set.
    error AccountantAlreadySet();

    /// @notice Thrown when an unauthorized address tries to set permissions.
    error NotPermissionSetter();

    /// @notice Thrown when trying to unshutdown a gauge that is not shutdown.
    error GaugeNotShutdown();

    /// @notice Thrown when trying to shutdown a gauge that is already shutdown.
    error GaugeAlreadyShutdown();

    /// @notice Thrown when trying to set an allocation target that is already whitelisted.
    error InvalidAllocationTarget();

    //////////////////////////////////////////////////////
    // --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Ensures only authorized registrars or owner can register vaults.
    modifier onlyRegistrar() {
        require(registrar[msg.sender] || msg.sender == owner(), OnlyRegistrar());
        _;
    }

    /// @notice Ensures only authorized permission setters can modify permissions.
    modifier onlyPermissionSetter() {
        require(permissionSetters[msg.sender] || msg.sender == owner(), NotPermissionSetter());
        _;
    }

    constructor(address owner) Ownable(owner) {}

    //////////////////////////////////////////////////////
    // --- PERMISSION MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Sets or revokes registrar permission for an address.
    /// @param  registrar_ The registrar address.
    /// @param  allowed Whether the registrar is allowed to register vaults.
    /// @custom:reverts Throws an error if the registrar address is zero.
    function setRegistrar(address registrar_, bool allowed) external onlyOwner {
        require(registrar_ != address(0), ZeroAddress());
        registrar[registrar_] = allowed;
        emit RegistrarPermissionSet(registrar_, allowed);
    }

    /// @notice Sets or revokes permission setter status for an address.
    /// @param  setter The permission setter address.
    /// @param  allowed Whether the address is allowed to set permissions.
    /// @custom:reverts Throws an error if the setter address is zero.
    function setPermissionSetter(address setter, bool allowed) external onlyOwner {
        require(setter != address(0), ZeroAddress());
        permissionSetters[setter] = allowed;
        emit PermissionSetterSet(setter, allowed);
    }

    /// @notice Sets a permission for a contract, caller, and function selector.
    /// @param  target The contract address where the permission is valid.
    /// @param  caller The caller address that is allowed to call the function.
    /// @param  selector The function selector that is being allowed or disallowed.
    /// @param  allowed Whether the caller is allowed to call the function.
    /// @custom:reverts Throws an error if the target or caller address is zero, or if the caller is not a permission setter.
    function setPermission(address target, address caller, bytes4 selector, bool allowed)
        external
        onlyPermissionSetter
    {
        require(target != address(0) && caller != address(0), ZeroAddress());
        _permissions[target][caller][selector] = allowed;
        emit PermissionSet(target, caller, selector, allowed);
    }

    //////////////////////////////////////////////////////
    // --- PROTOCOL COMPONENTS MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Sets a protocol strategy.
    /// @param  protocolId The protocol identifier.
    /// @param  strategy The strategy address.
    /// @custom:reverts Throws an error if the _strategy address is zero.
    function setStrategy(bytes4 protocolId, address strategy) external onlyOwner {
        require(strategy != address(0), ZeroAddress());
        _protocolComponents[protocolId].strategy = strategy;
        emit ProtocolComponentSet(protocolId, "Strategy", strategy);
    }

    /// @notice Sets a protocol allocator.
    /// @param  protocolId The protocol identifier.
    /// @param  allocator The allocator address.
    /// @custom:reverts Throws an error if the allocator address is zero.
    function setAllocator(bytes4 protocolId, address allocator) external onlyOwner {
        require(allocator != address(0), ZeroAddress());
        _protocolComponents[protocolId].allocator = allocator;
        emit ProtocolComponentSet(protocolId, "Allocator", allocator);
    }

    /// @notice Sets a protocol accountant.
    /// @dev    Accountant is immutable once set to prevent reward accounting disruption.
    /// @param  protocolId The protocol identifier.
    /// @param  accountant The accountant address.
    /// @custom:reverts Throws an error if the accountant address is zero or if it was previously set.
    function setAccountant(bytes4 protocolId, address accountant) external onlyOwner {
        require(accountant != address(0), ZeroAddress());
        require(_protocolComponents[protocolId].accountant == address(0), AccountantAlreadySet());

        _protocolComponents[protocolId].accountant = accountant;
        emit ProtocolComponentSet(protocolId, "Accountant", accountant);
    }

    /// @notice Sets a protocol fee receiver.
    /// @param  protocolId The protocol identifier.
    /// @param  feeReceiver The fee receiver address.
    /// @custom:reverts Throws an error if the feeReceiver address is zero.
    function setFeeReceiver(bytes4 protocolId, address feeReceiver) external onlyOwner {
        require(feeReceiver != address(0), ZeroAddress());
        _protocolComponents[protocolId].feeReceiver = feeReceiver;
        emit ProtocolComponentSet(protocolId, "FeeReceiver", feeReceiver);
    }

    /// @notice Sets a protocol factory.
    /// @param  protocolId The protocol identifier.
    /// @param  factory The factory address.
    /// @custom:reverts Throws an error if the factory address is zero.
    function setFactory(bytes4 protocolId, address factory) external onlyOwner {
        require(factory != address(0), ZeroAddress());
        _protocolComponents[protocolId].factory = factory;
        emit ProtocolComponentSet(protocolId, "Factory", factory);
    }

    /// @notice Sets a protocol locker.
    /// @param  protocolId The protocol identifier.
    /// @param  locker The locker address.
    /// @custom:reverts Throws an error if the locker address is zero.
    function setLocker(bytes4 protocolId, address locker) external onlyOwner {
        require(locker != address(0), ZeroAddress());
        _protocolComponents[protocolId].locker = locker;
        emit ProtocolComponentSet(protocolId, "Locker", locker);
    }

    /// @notice Sets a protocol gateway
    /// @param  protocolId The protocol identifier
    /// @param  gateway The gateway address
    /// @custom:reverts Throws an error if the gateway address is zero.
    function setGateway(bytes4 protocolId, address gateway) external onlyOwner {
        require(gateway != address(0), ZeroAddress());
        _protocolComponents[protocolId].gateway = gateway;
        emit ProtocolComponentSet(protocolId, "Gateway", gateway);
    }

    //////////////////////////////////////////////////////
    // --- VAULT REGISTRATION & SHUTDOWN
    //////////////////////////////////////////////////////

    /// @notice Registers a vault for a gauge.
    /// @dev    Creates the association between an external gauge and our vault system.
    /// @param  gauge_ The gauge address (external protocol's staking contract).
    /// @param  vault The vault address (our ERC4626 vault).
    /// @param  asset The asset address (Token that users deposit).
    /// @param  rewardReceiver The reward receiver address (receives extra rewards from gauge).
    /// @param  protocolId The protocol identifier for the gauge.
    /// @custom:reverts Throws an error if any of the addresses are zero.
    function registerVault(address gauge_, address vault, address asset, address rewardReceiver, bytes4 protocolId)
        external
        onlyRegistrar
    {
        require(
            gauge_ != address(0) && vault != address(0) && asset != address(0) && rewardReceiver != address(0),
            ZeroAddress()
        );

        Gauge storage g = gauge[gauge_];
        g.vault = vault;
        g.asset = asset;
        g.protocolId = protocolId;
        g.rewardReceiver = rewardReceiver;

        emit VaultRegistered(gauge_, vault, asset, rewardReceiver, protocolId);
    }

    /// @notice Whitelists an allocation target for a gauge.
    /// @dev    Strategies can only send funds to whitelisted targets for security.
    /// @param  gauge The gauge address.
    /// @param  target The target address (e.g., locker or sidecar contract).
    /// @custom:reverts InvalidAllocationTarget if target is already whitelisted.
    function setValidAllocationTarget(address gauge, address target) external onlyRegistrar {
        require(!_isValidAllocationTargets[gauge][target], InvalidAllocationTarget());

        _isValidAllocationTargets[gauge][target] = true;
    }

    /// @notice Removes an allocation target from the whitelist.
    /// @dev    Used when a target is no longer needed or trusted.
    /// @param  gauge The gauge address.
    /// @param  target The target address to remove.
    /// @custom:reverts InvalidAllocationTarget if target is not currently whitelisted.
    function removeValidAllocationTarget(address gauge, address target) external onlyRegistrar {
        require(_isValidAllocationTargets[gauge][target], InvalidAllocationTarget());

        _isValidAllocationTargets[gauge][target] = false;
    }

    /// @notice Emergency shutdown for a specific gauge.
    /// @dev    Prevents new deposits while allowing withdrawals for user fund recovery.
    /// @param  gauge_ The gauge address to shut down.
    /// @custom:reverts GaugeAlreadyShutdown if gauge was previously shutdown.
    function shutdown(address gauge_) external onlyOwner {
        Gauge storage g = gauge[gauge_];
        require(!g.isShutdown, GaugeAlreadyShutdown());

        gauge[gauge_].isShutdown = true;

        // Shutdown the gauge and withdraw all funds.
        IStrategy(_protocolComponents[g.protocolId].strategy).shutdown(gauge_);

        emit GaugeShutdown(gauge_);
    }

    /// @notice Unshuts down a gauge.
    /// @dev    Allows a previously shutdown gauge to resume operations.
    /// @param  gauge_ The gauge address to unshut down.
    /// @custom:reverts GaugeNotShutdown if gauge was not previously shutdown.
    function unshutdown(address gauge_) external onlyOwner {
        require(gauge[gauge_].isShutdown, GaugeNotShutdown());

        // Mark the gauge as not shutdown.
        gauge[gauge_].isShutdown = false;

        // Resume the vault operations.
        IRewardVault(gauge[gauge_].vault).resumeVault();

        emit GaugeUnshutdown(gauge_);
    }

    /// @notice Pauses deposits for a specific protocol.
    /// @dev    Withdrawals remain functional during pause.
    /// @param  protocolId The protocol identifier to pause.
    function pause(bytes4 protocolId) external onlyOwner {
        isPaused[protocolId] = true;
        emit Paused(protocolId);
    }

    /// @notice Unpauses deposits for a specific protocol.
    /// @param  protocolId The protocol identifier to unpause.
    function unpause(bytes4 protocolId) external onlyOwner {
        isPaused[protocolId] = false;
        emit Unpaused(protocolId);
    }

    //////////////////////////////////////////////////////
    // --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Returns the strategy address for a protocol.
    /// @param  protocolId The protocol identifier.
    /// @return _ The strategy address.
    function strategy(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].strategy;
    }

    /// @notice Returns the allocator address for a protocol.
    /// @param  protocolId The protocol identifier.
    /// @return _ The allocator address.
    function allocator(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].allocator;
    }

    /// @notice Returns the accountant address for a protocol.
    /// @param  protocolId The protocol identifier.
    /// @return _ The accountant address.
    function accountant(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].accountant;
    }

    /// @notice Returns the fee receiver address for a protocol.
    /// @param  protocolId The protocol identifier.
    /// @return _ The fee receiver address.
    function feeReceiver(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].feeReceiver;
    }

    /// @notice Returns the factory address for a protocol.
    /// @param  protocolId The protocol identifier.
    /// @return _ The factory address.
    function factory(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].factory;
    }

    /// @notice Returns the locker for a given protocol.
    /// @param  protocolId The protocol identifier.
    /// @return _ The locker address.
    function locker(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].locker;
    }

    /// @notice Returns the gateway for a given protocol.
    /// @param  protocolId The protocol identifier.
    /// @return _ The locker address.
    function gateway(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].gateway;
    }

    /// @notice Checks if an address is an authorized registrar.
    /// @param  registrar_ The address to check.
    /// @return _ Whether the address is an authorized registrar.
    function isRegistrar(address registrar_) external view returns (bool) {
        return registrar[registrar_];
    }

    /// @notice Returns the vault address for a gauge.
    /// @param  gauge_ The gauge address.
    /// @return _ The vault address.
    function vault(address gauge_) external view returns (address) {
        return gauge[gauge_].vault;
    }

    /// @notice Returns the reward receiver address for a gauge.
    /// @param  gauge_ The gauge address.
    /// @return _ The reward receiver address.
    function rewardReceiver(address gauge_) external view returns (address) {
        return gauge[gauge_].rewardReceiver;
    }

    /// @notice Returns the asset address for a gauge.
    /// @param  gauge_ The gauge address.
    /// @return _ The asset address.
    function asset(address gauge_) external view returns (address) {
        return gauge[gauge_].asset;
    }

    /// @notice Checks if a caller is allowed to call a function on a contract.
    /// @param  target The contract address.
    /// @param  caller The caller address.
    /// @param  selector The function selector.
    /// @return _ Whether the caller is allowed.
    function allowed(address target, address caller, bytes4 selector) external view returns (bool) {
        return _permissions[target][caller][selector] || caller == owner();
    }

    /// @notice Checks if a gauge is shutdown.
    /// @dev    Returns true if either the gauge itself or its protocol is shutdown.
    /// @param  gauge_ The gauge address.
    /// @return _ Whether the gauge is shutdown.
    function isShutdown(address gauge_) external view returns (bool) {
        return gauge[gauge_].isShutdown;
    }

    /// @notice Checks if a target is a valid allocation target for a gauge
    /// @param  gauge The gauge address
    /// @param  target The target address
    /// @return _ Whether the target is a valid allocation target
    function isValidAllocationTarget(address gauge, address target) external view returns (bool) {
        return _isValidAllocationTargets[gauge][target];
    }
}
