// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Governance} from "common/governance/Governance.sol";

contract VoterPermissionManager is Governance {
    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @dev Instead of using a traditional mapping that hashes the key to calculate the slot,
    ///      we directly use the unique identifier of each module as the storage slot.
    ///
    ///      The storage buffer exists to avoid future collisions. Note the owner of this
    ///      contract takes one slot in storage (slot 0).
    ///
    ///      The value of the buffer is equal to the keccak256 hash of the constant
    ///      string ""STAKEDAO.LOCKER.V2.VOTER_ALLOWANCE_MANAGER.V1"", meaning the modules will be
    ///      stored starting at slot `0x65a8012b7737dd00fb2623a75e13d3926cb7a6c59e6b502af4b6718938bb9be4`.
    ///      This is a gas cost optimization made possible due to the simplicity of the storage layout.
    bytes32 internal constant BUFFER = keccak256("STAKEDAO.LOCKER.V2.VOTER_ALLOWANCE_MANAGER.V1");

    ////////////////////////////////////////////////////////////////
    /// --- STATE
    ///////////////////////////////////////////////////////////////

    /**
     * @notice Enum representing the different permission levels for voter actions.
     * @dev
     * - `NONE`: Default permission. The address cannot call any permissioned functions.
     * - `PROPOSALS_ONLY`: The address can call functions that interact with proposals, e.g., voting on protocol proposals.
     * - `GAUGES_ONLY`: The address can call functions that interact with gauges, e.g., voting for gauge weights.
     * - `ALL`: The address can call all permissioned functions, including both proposal-related and gauge-related actions.
     */
    enum Permission {
        NONE, // 0: No permissions granted (default)
        PROPOSALS_ONLY, // 1: Can interact with proposals (e.g., {CurveVoter} functions)
        GAUGES_ONLY, // 2: Can interact with gauges (e.g., {VoterBase-voteGauges})
        ALL // 3: Can interact with all permissioned functions

    }

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when a permission is set for an address
    /// @param account The address of the account
    /// @param permission The permission
    event PermissionSet(address indexed account, Permission indexed permission);

    /// @notice Error emitted when a caller is not authorized
    error NOT_AUTHORIZED();

    /// @notice Error emitted when the length of the addresses and permissions are not the same
    error INVALID_LENGTH();

    /// @notice Error emitted when an unknown permission is requested
    /// @dev Should never happen
    error UNKNOWN_PERMISSION();

    constructor(address _governance) Governance(_governance) {}

    ////////////////////////////////////////////////////////////////
    /// --- MODIFIERS
    ///////////////////////////////////////////////////////////////

    /// @notice Modifier to check if the caller has proposals or all permission
    modifier hasProposalsOrAllPermission() {
        Permission permission = getPermission(msg.sender);
        require(permission == Permission.PROPOSALS_ONLY || permission == Permission.ALL, NOT_AUTHORIZED());
        _;
    }

    /// @notice Modifier to check if the caller has gauges or all permission
    modifier hasGaugesOrAllPermission() {
        Permission permission = getPermission(msg.sender);
        require(permission == Permission.GAUGES_ONLY || permission == Permission.ALL, NOT_AUTHORIZED());
        _;
    }

    ////////////////////////////////////////////////////////////////
    /// --- PUBLIC FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Sets the permission for an address
    /// @param _address The address of the account
    /// @param _permission The permission
    function setPermission(address _address, Permission _permission) public onlyGovernance {
        bytes32 buffer = BUFFER;

        assembly ("memory-safe") {
            sstore(add(buffer, _address), _permission)
        }

        emit PermissionSet(_address, _permission);
    }

    /// @notice Sets the permissions for a list of addresses
    /// @param _addresses The addresses of the accounts
    /// @param _permissions The permissions
    function setPermissions(address[] calldata _addresses, Permission[] calldata _permissions)
        external
        onlyGovernance
    {
        require(_addresses.length == _permissions.length, INVALID_LENGTH());

        for (uint256 i; i < _addresses.length; i++) {
            setPermission(_addresses[i], _permissions[i]);
        }
    }

    /// @notice Gets the permission for an address
    /// @param _address The address of the account
    /// @return permission The permission
    function getPermission(address _address) public view returns (Permission permission) {
        bytes32 buffer = BUFFER;
        assembly ("memory-safe") {
            permission := sload(add(buffer, _address))
        }
    }

    /// @notice Gets the permission label for an address
    /// @dev This function is a helper for off-chain tools
    /// @param _address The address of the account
    /// @return The permission label
    function getPermissionLabel(address _address) external view returns (string memory) {
        Permission permission = getPermission(_address);

        if (permission == Permission.ALL) return "ALL";
        else if (permission == Permission.PROPOSALS_ONLY) return "PROPOSALS_ONLY";
        else if (permission == Permission.GAUGES_ONLY) return "GAUGES_ONLY";
        else if (permission == Permission.NONE) return "NONE";
        else revert UNKNOWN_PERMISSION();
    }
}
