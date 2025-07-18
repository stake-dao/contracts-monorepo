// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IRewardVault} from "src/interfaces/IRewardVault.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";

/// @title ProtocolController
/// @author Stake DAO
/// @notice Central registry for protocol components and permissions management
/// @dev Manages protocol components, permissions, and shutdown functionality
contract ProtocolController is IProtocolController, Ownable2Step {
    //////////////////////////////////////////////////////
    // --- STORAGE STRUCTURES
    //////////////////////////////////////////////////////

    /// @notice Stores the core components for each protocol integration
    /// @dev Each protocol (Curve, Balancer, etc.) has its own set of components
    struct ProtocolComponents {
        address strategy;
        address allocator;
        address accountant;
        address feeReceiver;
        address factory;
    }

    /// @notice Links a gauge to its associated vault and protocol
    /// @dev A gauge is the external yield source (e.g., Curve gauge) that the vault interacts with
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

    /// @notice Maps each gauge address to its configuration
    /// @dev This is the primary registry that links external gauges to our vault system
    mapping(address => Gauge) public gauge;

    /// @notice Authorized addresses that can register new vaults and set allocation targets
    /// @dev Typically factory contracts that need to create new vaults programmatically
    mapping(address => bool) public registrar;

    /// @notice Addresses authorized to manage granular function-level permissions
    /// @dev Enables delegation of permission management without giving full ownership
    mapping(address => bool) public permissionSetters;

    /// @notice Core components for each protocol, indexed by protocol ID
    /// @dev Protocol ID is typically keccak256("PROTOCOL_NAME") truncated to bytes4
    mapping(bytes4 => ProtocolComponents) internal _protocolComponents;

    /// @notice Whitelisted allocation targets for each gauge
    /// @dev Strategies can only allocate funds to these pre-approved destinations (e.g., locker, sidecars)
    mapping(address => mapping(address => bool)) internal _isValidAllocationTargets;

    /// @notice Granular permission system: contract -> caller -> function -> allowed
    /// @dev Enables fine-grained access control for specific function calls
    mapping(address => mapping(address => mapping(bytes4 => bool))) internal _permissions;

    /// @notice Per-protocol deposit pause state
    /// @dev When true for a protocol, deposits are paused but withdrawals remain functional
    mapping(bytes4 => bool) public isPaused;

    //////////////////////////////////////////////////////
    // --- ERRORS & EVENTS
    //////////////////////////////////////////////////////

    /// @notice Event emitted when a protocol component is set
    /// @param protocolId The protocol identifier
    /// @param componentId The component identifier ("Strategy", "Allocator", "Accountant", "FeeReceiver")
    /// @param component The component address
    event ProtocolComponentSet(bytes4 indexed protocolId, string indexed componentId, address indexed component);

    /// @notice Event emitted when a vault is registered
    /// @param gauge The gauge address
    /// @param vault The vault address
    /// @param asset The asset address
    /// @param rewardReceiver The reward receiver address
    /// @param protocolId The protocol identifier
    event VaultRegistered(
        address indexed gauge, address indexed vault, address indexed asset, address rewardReceiver, bytes4 protocolId
    );

    /// @notice Event emitted when a gauge is shutdown
    /// @param gauge The gauge address
    event GaugeShutdown(address indexed gauge);

    /// @notice Event emitted when a gauge is unshut down
    /// @param gauge The gauge address
    event GaugeUnshutdown(address indexed gauge);

    /// @notice Event emitted when a protocol is shutdown
    /// @param protocolId The protocol identifier
    event ProtocolShutdown(bytes4 indexed protocolId);

    /// @notice Event emitted when a permission is set
    /// @param contractAddress The contract address
    /// @param caller The caller address
    /// @param selector The function selector
    /// @param allowed Whether the registrar is allowed to register vaults
    event PermissionSet(address indexed contractAddress, address indexed caller, bytes4 indexed selector, bool allowed);

    /// @notice Event emitted when a registrar permission is set
    /// @param registrar The registrar address
    /// @param allowed Whether the registrar is allowed to register vaults
    event RegistrarPermissionSet(address indexed registrar, bool allowed);

    /// @notice Event emitted when a permission setter is set
    /// @param setter The permission setter address
    /// @param allowed Whether the permission setter is allowed to set permissions
    event PermissionSetterSet(address indexed setter, bool allowed);

    /// @notice Event emitted when deposits are paused for a protocol
    /// @param protocolId The protocol identifier
    event Paused(bytes4 indexed protocolId);

    /// @notice Event emitted when deposits are unpaused for a protocol
    /// @param protocolId The protocol identifier
    event Unpaused(bytes4 indexed protocolId);

    /// @notice Thrown when a non-strategy calls a strategy-only function
    error OnlyStrategy();

    /// @notice Thrown when a non-registrar calls a registrar-only function
    error OnlyRegistrar();

    /// @notice Thrown when a zero address is used
    error ZeroAddress();

    /// @notice Thrown when an accountant is already set
    error AccountantAlreadySet();

    /// @notice Thrown when an unauthorized address tries to set permissions
    error NotPermissionSetter();

    /// @notice Thrown when a gauge is not shutdown
    error GaugeNotShutdown();

    /// @notice Thrown when a gauge is not fully withdrawn
    error GaugeNotFullyWithdrawn();

    /// @notice Thrown when a gauge is already shutdown
    error GaugeAlreadyShutdown();

    /// @notice Thrown when an invalid allocation target is set
    error InvalidAllocationTarget();

    /// @notice Thrown when a protocol is already shutdown
    error ProtocolAlreadyShutdown();

    /// @notice Thrown when a gauge is already fully withdrawn
    error GaugeAlreadyFullyWithdrawn();

    //////////////////////////////////////////////////////
    // --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Ensures only authorized registrars or owner can register vaults
    /// @dev Used by factory contracts during vault deployment
    modifier onlyRegistrar() {
        require(registrar[msg.sender] || msg.sender == owner(), OnlyRegistrar());
        _;
    }

    /// @notice Ensures only the protocol's strategy can call gauge-specific functions
    /// @dev Prevents unauthorized contracts from marking gauges as withdrawn
    modifier onlyStrategy(address _gauge) {
        address _strategy = _protocolComponents[gauge[_gauge].protocolId].strategy;
        require(msg.sender == _strategy, OnlyStrategy());
        _;
    }

    /// @notice Ensures only authorized permission setters can modify permissions
    /// @dev Allows delegation of permission management without full ownership
    modifier onlyPermissionSetter() {
        require(permissionSetters[msg.sender] || msg.sender == owner(), NotPermissionSetter());
        _;
    }

    //////////////////////////////////////////////////////
    // --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor for the ProtocolController
    /// @dev Initializes the owner of the contract
    constructor(address _owner) Ownable(_owner) {}

    //////////////////////////////////////////////////////
    // --- PERMISSION MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Sets or revokes registrar permission for an address
    /// @param _registrar The registrar address
    /// @param _allowed Whether the registrar is allowed to register vaults
    /// @custom:reverts ZeroAddress if the registrar address is zero
    function setRegistrar(address _registrar, bool _allowed) external onlyOwner {
        require(_registrar != address(0), ZeroAddress());
        registrar[_registrar] = _allowed;
        emit RegistrarPermissionSet(_registrar, _allowed);
    }

    /// @notice Sets or revokes permission setter status for an address
    /// @param _setter The permission setter address
    /// @param _allowed Whether the address is allowed to set permissions
    /// @custom:reverts ZeroAddress Throws an error if the permission setter address is zero
    function setPermissionSetter(address _setter, bool _allowed) external onlyOwner {
        require(_setter != address(0), ZeroAddress());
        permissionSetters[_setter] = _allowed;
        emit PermissionSetterSet(_setter, _allowed);
    }

    /// @notice Sets a permission for a contract, caller, and function selector
    /// @param _contract The contract address
    /// @param _caller The caller address
    /// @param _selector The function selector
    /// @param _allowed Whether the caller is allowed to call the function
    /// @custom:reverts ZeroAddress if the contract or caller address is zero
    function setPermission(address _contract, address _caller, bytes4 _selector, bool _allowed)
        external
        onlyPermissionSetter
    {
        require(_contract != address(0) && _caller != address(0), ZeroAddress());
        _permissions[_contract][_caller][_selector] = _allowed;
        emit PermissionSet(_contract, _caller, _selector, _allowed);
    }

    //////////////////////////////////////////////////////
    // --- PROTOCOL COMPONENT MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Sets a protocol strategy
    /// @param protocolId The protocol identifier
    /// @param _strategy The strategy address
    /// @custom:reverts ZeroAddress if the strategy address is zero
    function setStrategy(bytes4 protocolId, address _strategy) external onlyOwner {
        require(_strategy != address(0), ZeroAddress());
        _protocolComponents[protocolId].strategy = _strategy;
        emit ProtocolComponentSet(protocolId, "Strategy", _strategy);
    }

    /// @notice Sets a protocol allocator
    /// @param protocolId The protocol identifier
    /// @param _allocator The allocator address
    /// @custom:reverts ZeroAddress if the allocator address is zero
    function setAllocator(bytes4 protocolId, address _allocator) external onlyOwner {
        require(_allocator != address(0), ZeroAddress());
        _protocolComponents[protocolId].allocator = _allocator;
        emit ProtocolComponentSet(protocolId, "Allocator", _allocator);
    }

    /// @notice Sets a protocol accountant
    /// @dev Accountant is immutable once set to prevent reward accounting disruption
    /// @param protocolId The protocol identifier
    /// @param _accountant The accountant address
    /// @custom:reverts ZeroAddress if the accountant address is zero
    /// @custom:reverts AccountantAlreadySet if accountant was previously set
    function setAccountant(bytes4 protocolId, address _accountant) external onlyOwner {
        require(_accountant != address(0), ZeroAddress());
        require(_protocolComponents[protocolId].accountant == address(0), AccountantAlreadySet());

        _protocolComponents[protocolId].accountant = _accountant;
        emit ProtocolComponentSet(protocolId, "Accountant", _accountant);
    }

    /// @notice Sets a protocol fee receiver
    /// @param protocolId The protocol identifier
    /// @param _feeReceiver The fee receiver address
    /// @custom:reverts ZeroAddress if the fee receiver address is zero
    function setFeeReceiver(bytes4 protocolId, address _feeReceiver) external onlyOwner {
        require(_feeReceiver != address(0), ZeroAddress());
        _protocolComponents[protocolId].feeReceiver = _feeReceiver;
        emit ProtocolComponentSet(protocolId, "FeeReceiver", _feeReceiver);
    }

    /// @notice Sets a protocol factory
    /// @param protocolId The protocol identifier
    /// @param _factory The factory address
    /// @custom:reverts ZeroAddress if the factory address is zero
    function setFactory(bytes4 protocolId, address _factory) external onlyOwner {
        require(_factory != address(0), ZeroAddress());
        _protocolComponents[protocolId].factory = _factory;
        emit ProtocolComponentSet(protocolId, "Factory", _factory);
    }

    //////////////////////////////////////////////////////
    // --- VAULT REGISTRATION & SHUTDOWN
    //////////////////////////////////////////////////////

    /// @notice Registers a vault for a gauge
    /// @dev Creates the association between an external gauge and our vault system
    /// @param _gauge The gauge address (external protocol's staking contract)
    /// @param _vault The vault address (our ERC4626 vault)
    /// @param _asset The asset address (LP token that users deposit)
    /// @param _rewardReceiver The reward receiver address (receives extra rewards from gauge)
    /// @param _protocolId The protocol identifier for the gauge
    /// @custom:reverts ZeroAddress if any address parameter is zero
    function registerVault(address _gauge, address _vault, address _asset, address _rewardReceiver, bytes4 _protocolId)
        external
        onlyRegistrar
    {
        require(
            _gauge != address(0) && _vault != address(0) && _asset != address(0) && _rewardReceiver != address(0),
            ZeroAddress()
        );

        // Single SSTORE operation for gas efficiency
        Gauge storage g = gauge[_gauge];
        g.vault = _vault;
        g.asset = _asset;
        g.protocolId = _protocolId;
        g.rewardReceiver = _rewardReceiver;

        emit VaultRegistered(_gauge, _vault, _asset, _rewardReceiver, _protocolId);
    }

    /// @notice Whitelists an allocation target for a gauge
    /// @dev Strategies can only send funds to whitelisted targets for security
    /// @param _gauge The gauge address
    /// @param _target The target address (e.g., locker or sidecar contract)
    /// @custom:reverts InvalidAllocationTarget if target is already whitelisted
    function setValidAllocationTarget(address _gauge, address _target) external onlyRegistrar {
        require(!_isValidAllocationTargets[_gauge][_target], InvalidAllocationTarget());

        _isValidAllocationTargets[_gauge][_target] = true;
    }

    /// @notice Removes an allocation target from the whitelist
    /// @dev Used when a target is no longer needed or trusted
    /// @param _gauge The gauge address
    /// @param _target The target address to remove
    /// @custom:reverts InvalidAllocationTarget if target is not currently whitelisted
    function removeValidAllocationTarget(address _gauge, address _target) external onlyRegistrar {
        require(_isValidAllocationTargets[_gauge][_target], InvalidAllocationTarget());

        _isValidAllocationTargets[_gauge][_target] = false;
    }

    /// @notice Emergency shutdown for a specific gauge
    /// @dev Prevents new deposits while allowing withdrawals for user fund recovery
    /// @param _gauge The gauge address to shut down
    /// @custom:reverts GaugeAlreadyShutdown if gauge was previously shutdown
    function shutdown(address _gauge) external onlyOwner {
        Gauge storage g = gauge[_gauge];
        require(!g.isShutdown, GaugeAlreadyShutdown());

        gauge[_gauge].isShutdown = true;

        address _strategy = _protocolComponents[g.protocolId].strategy;

        // Shutdown the gauge and withdraw all funds.
        IStrategy(_strategy).shutdown(_gauge);

        emit GaugeShutdown(_gauge);
    }

    /// @notice Unshuts down a gauge
    /// @dev Allows a previously shutdown gauge to resume operations
    /// @param _gauge The gauge address to unshut down
    /// @custom:reverts GaugeNotShutdown if gauge was not previously shutdown
    function unshutdown(address _gauge) external onlyOwner {
        require(gauge[_gauge].isShutdown, GaugeNotShutdown());

        address _vault = gauge[_gauge].vault;

        gauge[_gauge].isShutdown = false;

        // Resume the vault operations
        IRewardVault(_vault).resumeVault();

        emit GaugeUnshutdown(_gauge);
    }

    /// @notice Pauses deposits for a specific protocol
    /// @dev Withdrawals remain functional during pause
    /// @param protocolId The protocol identifier to pause
    function pause(bytes4 protocolId) external onlyOwner {
        isPaused[protocolId] = true;
        emit Paused(protocolId);
    }

    /// @notice Unpauses deposits for a specific protocol
    /// @param protocolId The protocol identifier to unpause
    function unpause(bytes4 protocolId) external onlyOwner {
        isPaused[protocolId] = false;
        emit Unpaused(protocolId);
    }

    //////////////////////////////////////////////////////
    // --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Returns the strategy address for a protocol
    /// @param protocolId The protocol identifier
    /// @return _ The strategy address
    function strategy(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].strategy;
    }

    /// @notice Returns the allocator address for a protocol
    /// @param protocolId The protocol identifier
    /// @return _ The allocator address
    function allocator(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].allocator;
    }

    /// @notice Returns the accountant address for a protocol
    /// @param protocolId The protocol identifier
    /// @return _ The accountant address
    function accountant(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].accountant;
    }

    /// @notice Returns the fee receiver address for a protocol
    /// @param protocolId The protocol identifier
    /// @return _ The fee receiver address
    function feeReceiver(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].feeReceiver;
    }

    /// @notice Returns the factory address for a protocol
    /// @param protocolId The protocol identifier
    /// @return _ The factory address
    function factory(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].factory;
    }

    /// @notice Checks if an address is an authorized registrar
    /// @param _registrar The address to check
    /// @return _ Whether the address is an authorized registrar
    function isRegistrar(address _registrar) external view returns (bool) {
        return registrar[_registrar];
    }

    /// @notice Returns the vault address for a gauge
    /// @param _gauge The gauge address
    /// @return _ The vault address
    function vaults(address _gauge) external view returns (address) {
        return gauge[_gauge].vault;
    }

    /// @notice Returns the reward receiver address for a gauge
    /// @param _gauge The gauge address
    /// @return _ The reward receiver address
    function rewardReceiver(address _gauge) external view returns (address) {
        return gauge[_gauge].rewardReceiver;
    }

    /// @notice Returns the asset address for a gauge
    /// @param _gauge The gauge address
    /// @return _ The asset address
    function asset(address _gauge) external view returns (address) {
        return gauge[_gauge].asset;
    }

    /// @notice Checks if a caller is allowed to call a function on a contract
    /// @param _contract The contract address
    /// @param _caller The caller address
    /// @param _selector The function selector
    /// @return _ Whether the caller is allowed
    function allowed(address _contract, address _caller, bytes4 _selector) external view returns (bool) {
        return _permissions[_contract][_caller][_selector] || _caller == owner();
    }

    /// @notice Checks if a gauge is shutdown
    /// @dev Returns true if either the gauge itself or its protocol is shutdown
    /// @param _gauge The gauge address
    /// @return _ Whether the gauge is shutdown
    function isShutdown(address _gauge) external view returns (bool) {
        return gauge[_gauge].isShutdown;
    }

    /// @notice Checks if a target is a valid allocation target for a gauge
    /// @param _gauge The gauge address
    /// @param _target The target address
    /// @return _ Whether the target is a valid allocation target
    function isValidAllocationTarget(address _gauge, address _target) external view returns (bool) {
        return _isValidAllocationTargets[_gauge][_target];
    }
}
