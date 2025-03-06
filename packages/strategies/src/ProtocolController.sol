// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title ProtocolController
/// @author Stake DAO
/// @notice Central registry for protocol components and permissions management
/// @dev Manages protocol components, permissions, and shutdown functionality
contract ProtocolController is IProtocolController, Ownable2Step {
    //////////////////////////////////////////////////////
    /// --- STORAGE STRUCTURES
    //////////////////////////////////////////////////////

    /// @notice Struct to store protocol components in a single storage slot
    struct ProtocolComponents {
        address strategy;
        address allocator;
        address harvester;
        address accountant;
        address feeReceiver;
        bool isShutdown;
    }

    /// @notice Struct to store gauge-related information (optimized for packing)
    struct Gauge {
        address vault;
        address asset;
        address rewardReceiver;
        bytes4 protocolId;
        bool isShutdown;
    }

    //////////////////////////////////////////////////////
    /// --- STATE VARIABLES
    //////////////////////////////////////////////////////
    /// @notice Mapping of gauge address to Gauge struct
    mapping(address => Gauge) public gauge;

    /// @notice Mapping of registrar addresses to their permission status (1 = allowed, 0 = not allowed)
    mapping(address => bool) public registrar;

    /// @notice Mapping of protocol ID to its components
    mapping(bytes4 => ProtocolComponents) private _protocolComponents;

    /// @notice Mapping of contract to caller to function selector to permission
    mapping(address => mapping(address => mapping(bytes4 => bool))) private _permissions;

    /// @notice Mapping of addresses that can set permissions
    mapping(address => bool) public permissionSetters;

    //////////////////////////////////////////////////////
    /// --- ERRORS & EVENTS
    //////////////////////////////////////////////////////

    /// @notice Event emitted when a protocol component is set
    event ProtocolComponentSet(bytes4 indexed protocolId, string componentType, address indexed component);

    /// @notice Event emitted when a vault is registered
    event VaultRegistered(address indexed gauge, address indexed vault, address indexed asset, bytes4 protocolId);

    /// @notice Event emitted when a gauge is shutdown
    event GaugeShutdown(address indexed gauge);

    /// @notice Event emitted when a protocol is shutdown
    event ProtocolShutdown(bytes4 indexed protocolId);

    /// @notice Event emitted when a permission is set
    event PermissionSet(address indexed contract_, address indexed caller, bytes4 indexed selector, bool allowed);

    /// @notice Event emitted when a registrar permission is set
    event RegistrarPermissionSet(address indexed registrar, bool allowed);

    /// @notice Event emitted when a permission setter is set
    event PermissionSetterSet(address indexed setter, bool allowed);

    /// @notice Thrown when a non-registrar calls a registrar-only function
    error OnlyRegistrar();

    /// @notice Thrown when a zero address is used
    error ZeroAddress();

    /// @notice Thrown when an unauthorized address tries to set permissions
    error NotPermissionSetter();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Modifier to restrict function access to registrars or owner
    modifier onlyRegistrar() {
        require(registrar[msg.sender], OnlyRegistrar());
        _;
    }

    /// @notice Modifier to restrict function access to permission setters or owner
    modifier onlyPermissionSetter() {
        require(permissionSetters[msg.sender] || msg.sender == owner(), NotPermissionSetter());
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor() Ownable(msg.sender) {}

    //////////////////////////////////////////////////////
    //////////////////////////////////////////////////////
    /// --- PERMISSION MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Sets or revokes registrar permission for an address
    /// @param _registrar The registrar address
    /// @param _allowed Whether the registrar is allowed to register vaults
    function setRegistrar(address _registrar, bool _allowed) external onlyOwner {
        require(_registrar != address(0), ZeroAddress());
        registrar[_registrar] = _allowed;
        emit RegistrarPermissionSet(_registrar, _allowed);
    }

    /// @notice Sets or revokes permission setter status for an address
    /// @param _setter The permission setter address
    /// @param _allowed Whether the address is allowed to set permissions
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
    function setPermission(address _contract, address _caller, bytes4 _selector, bool _allowed)
        external
        onlyPermissionSetter
    {
        require(_contract != address(0) && _caller != address(0), ZeroAddress());
        _permissions[_contract][_caller][_selector] = _allowed;
        emit PermissionSet(_contract, _caller, _selector, _allowed);
    }

    //////////////////////////////////////////////////////
    /// --- PROTOCOL COMPONENT MANAGEMENT
    //////////////////////////////////////////////////////

    /// @notice Sets a protocol strategy
    /// @param protocolId The protocol identifier
    /// @param _strategy The strategy address
    function setStrategy(bytes4 protocolId, address _strategy) external onlyOwner {
        require(_strategy != address(0), ZeroAddress());
        _protocolComponents[protocolId].strategy = _strategy;
        emit ProtocolComponentSet(protocolId, "Strategy", _strategy);
    }

    /// @notice Sets a protocol allocator
    /// @param protocolId The protocol identifier
    /// @param _allocator The allocator address
    function setAllocator(bytes4 protocolId, address _allocator) external onlyOwner {
        require(_allocator != address(0), ZeroAddress());
        _protocolComponents[protocolId].allocator = _allocator;
        emit ProtocolComponentSet(protocolId, "Allocator", _allocator);
    }

    /// @notice Sets a protocol harvester
    /// @param protocolId The protocol identifier
    /// @param _harvester The harvester address
    function setHarvester(bytes4 protocolId, address _harvester) external onlyOwner {
        require(_harvester != address(0), ZeroAddress());
        _protocolComponents[protocolId].harvester = _harvester;
        emit ProtocolComponentSet(protocolId, "Harvester", _harvester);
    }

    /// @notice Sets a protocol accountant
    /// @param protocolId The protocol identifier
    /// @param _accountant The accountant address
    function setAccountant(bytes4 protocolId, address _accountant) external onlyOwner {
        require(_accountant != address(0), ZeroAddress());
        _protocolComponents[protocolId].accountant = _accountant;
        emit ProtocolComponentSet(protocolId, "Accountant", _accountant);
    }

    /// @notice Sets a protocol fee receiver
    /// @param protocolId The protocol identifier
    /// @param _feeReceiver The fee receiver address
    function setFeeReceiver(bytes4 protocolId, address _feeReceiver) external onlyOwner {
        require(_feeReceiver != address(0), ZeroAddress());
        _protocolComponents[protocolId].feeReceiver = _feeReceiver;
        emit ProtocolComponentSet(protocolId, "FeeReceiver", _feeReceiver);
    }

    //////////////////////////////////////////////////////
    /// --- VAULT REGISTRATION & SHUTDOWN
    //////////////////////////////////////////////////////

    /// @notice Registers a vault for a gauge
    /// @param _gauge The gauge address
    /// @param _vault The vault address
    /// @param _asset The asset address
    /// @param _rewardReceiver The reward receiver address
    /// @param _protocolId The protocol identifier for the gauge
    /// @dev Can be called by the owner or by authorized registrar contracts
    function registerVault(address _gauge, address _vault, address _asset, address _rewardReceiver, bytes4 _protocolId)
        external
        onlyRegistrar
    {
        require(
            _gauge != address(0) && _vault != address(0) && _asset != address(0) && _rewardReceiver != address(0),
            ZeroAddress()
        );

        // Optimized storage writing
        Gauge storage g = gauge[_gauge];
        g.vault = _vault;
        g.asset = _asset;
        g.protocolId = _protocolId;
        g.rewardReceiver = _rewardReceiver;

        emit VaultRegistered(_gauge, _vault, _asset, _protocolId);
    }

    /// @notice Shuts down a gauge
    /// @param _gauge The gauge address to shut down
    function shutdown(address _gauge) external onlyOwner {
        gauge[_gauge].isShutdown = true;
        emit GaugeShutdown(_gauge);
    }

    /// @notice Shuts down a protocol
    /// @param protocolId The protocol identifier
    function shutdownProtocol(bytes4 protocolId) external onlyOwner {
        _protocolComponents[protocolId].isShutdown = true;
        emit ProtocolShutdown(protocolId);
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Returns the strategy address for a protocol
    /// @param protocolId The protocol identifier
    /// @return The strategy address
    function strategy(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].strategy;
    }

    /// @notice Returns the allocator address for a protocol
    /// @param protocolId The protocol identifier
    /// @return The allocator address
    function allocator(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].allocator;
    }

    /// @notice Returns the harvester address for a protocol
    /// @param protocolId The protocol identifier
    /// @return The harvester address
    function harvester(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].harvester;
    }

    /// @notice Returns the accountant address for a protocol
    /// @param protocolId The protocol identifier
    /// @return The accountant address
    function accountant(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].accountant;
    }

    /// @notice Returns the fee receiver address for a protocol
    /// @param protocolId The protocol identifier
    /// @return The fee receiver address
    function feeReceiver(bytes4 protocolId) external view returns (address) {
        return _protocolComponents[protocolId].feeReceiver;
    }

    /// @notice Checks if an address is an authorized registrar
    /// @param _registrar The address to check
    /// @return Whether the address is an authorized registrar
    function isRegistrar(address _registrar) external view returns (bool) {
        return registrar[_registrar];
    }

    /// @notice Returns the vault address for a gauge
    /// @param _gauge The gauge address
    /// @return The vault address
    function vaults(address _gauge) external view returns (address) {
        return gauge[_gauge].vault;
    }

    /// @notice Returns the reward receiver address for a gauge
    /// @param _gauge The gauge address
    /// @return The reward receiver address
    function rewardReceiver(address _gauge) external view returns (address) {
        return gauge[_gauge].rewardReceiver;
    }

    /// @notice Returns the asset address for a gauge
    /// @param _gauge The gauge address
    /// @return The asset address
    function asset(address _gauge) external view returns (address) {
        return gauge[_gauge].asset;
    }

    /// @notice Checks if a caller is allowed to call a function on a contract
    /// @param _contract The contract address
    /// @param _caller The caller address
    /// @param _selector The function selector
    /// @return Whether the caller is allowed
    function allowed(address _contract, address _caller, bytes4 _selector) external view returns (bool) {
        return _permissions[_contract][_caller][_selector] || _caller == owner();
    }

    /// @notice Checks if a protocol is shutdown
    /// @param protocolId The protocol identifier
    /// @return Whether the protocol is shutdown
    function isShutdownProtocol(bytes4 protocolId) external view returns (bool) {
        return _protocolComponents[protocolId].isShutdown;
    }

    /// @notice Checks if a gauge is shutdown
    /// @param _gauge The gauge address
    /// @return Whether the gauge is shutdown
    function isShutdown(address _gauge) external view returns (bool) {
        bytes4 protocolId = gauge[_gauge].protocolId;
        return gauge[_gauge].isShutdown || _protocolComponents[protocolId].isShutdown;
    }
}
