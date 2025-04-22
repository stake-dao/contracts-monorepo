// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IRouter} from "src/interfaces/IRouter.sol";
import {IRouterModule} from "src/interfaces/IRouterModule.sol";

/**
 * @title Staking Router
 * @notice One single entry point for all Staking V2 instances.
 * @dev This contract allows for the execution of arbitrary delegate calls to registered modules.
 */
contract Router is IRouter, Ownable {
    ///////////////////////////////////////////////////////////////
    // --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice The storage buffer for the modules
    /// @dev Instead of using a traditional mapping that hashes the key to calculate the slot,
    ///      we directly use the unique identifier of each module as the storage slot.
    ///
    ///      The storage buffer exists to avoid future collisions. Note the owner of this
    ///      contract takes one slot in storage (slot 0).
    ///
    ///      The value of the buffer is equal to the keccak256 hash of the constant
    ///      string "STAKEDAO.STAKING.V2.ROUTER.V1", meaning the modules will be
    ///      stored starting at slot `0x5fb198ff3ff065a7e746cc70c28b38b1f3eeaf1a559ede71c28b60a0759b061b`.
    ///      This is a gas cost optimization made possible due to the simplicity of the storage layout.
    bytes32 internal constant $buffer = keccak256("STAKEDAO.STAKING.V2.ROUTER.V1");
    string public constant version = "1.0.0";

    ///////////////////////////////////////////////////////////////
    // --- EVENTS - ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Emitted when a module is set
    /// @param identifier The unique identifier of the module (indexed value)
    /// @param module The address of the module
    /// @param name The name of the module
    event ModuleSet(uint8 indexed identifier, address module, string name);

    // @notice Thrown when a module is already set
    // @dev Only thrown when setting a module in safe mode

    error IdentifierAlreadyUsed(uint8 identifier);

    // @notice Thrown when trying to call a module that is not set
    error ModuleNotSet(uint8 identifier);

    constructor() Ownable(msg.sender) {}

    ///////////////////////////////////////////////////////////////
    // --- MODULES MANAGEMENT
    ///////////////////////////////////////////////////////////////

    /**
     * @notice Gets the storage buffer used to store the modules.
     *         The buffer acts as an offset for the storage of modules.
     * @return buffer The storage buffer
     */
    function getStorageBuffer() public pure returns (bytes32 buffer) {
        buffer = $buffer;
    }

    /// @notice Sets a module
    /// @dev The module is set at the storage slot `buffer + identifier`
    ///
    ///      While not enforced by the code, developers are expected to use
    ///      incremental identifiers when setting modules.
    ///      This allows modules to be enumerated using the `enumerateModules` helper.
    ///      Note that this is just a convention, and modules should be indexed off-chain for
    ///      efficiency and correctness.
    /// @param identifier The unique identifier of the module
    /// @param module The address of the module
    /// @custom:throws OwnableUnauthorizedAccount if the caller is not the owner
    function setModule(uint8 identifier, address module) public onlyOwner {
        bytes32 buffer = getStorageBuffer();
        assembly ("memory-safe") {
            sstore(add(buffer, identifier), module)
        }

        emit ModuleSet(identifier, module, IRouterModule(module).name());
    }

    /// @notice Sets a module in safe mode
    /// @dev The module can be set to address(0) to erase it
    /// @param identifier The unique identifier of the module
    /// @param module The address of the module
    /// @custom:throws OwnableUnauthorizedAccount if the caller is not the owner
    /// @custom:throws IdentifierAlreadyUsed if the identifier is already set
    function safeSetModule(uint8 identifier, address module) external onlyOwner {
        require(getModule(identifier) == address(0), IdentifierAlreadyUsed(identifier));

        setModule(identifier, module);
    }

    /// @notice Gets the module at the given identifier
    /// @param identifier The unique identifier of the module
    /// @return module The address of the module. Returns address(0) if the module is not set
    function getModule(uint8 identifier) public view returns (address module) {
        bytes32 buffer = getStorageBuffer();
        assembly ("memory-safe") {
            module := sload(add(buffer, identifier))
        }
    }

    /// @notice Gets the name of the module at the given identifier
    /// @param identifier The unique identifier of the module
    /// @return name The name of the module. Returns an empty string if the module is not set
    function getModuleName(uint8 identifier) public view returns (string memory name) {
        address module = getModule(identifier);
        if (module != address(0)) name = IRouterModule(module).name();
    }

    /// @notice Convenient function to enumerate the incrementally stored modules
    /// @dev Never call this function on-chain. It is only meant to be used off-chain for informational purposes.
    ///      This function should not replace off-chain indexing of the modules.
    ///
    ///      This function stops iterating when it encounters address(0). This means that
    ///      if the modules are not stored contiguously, this function will return only a subset of the modules.
    /// @return modules The concatenated addresses of the modules in a bytes array.
    ///                 The length of the returned bytes array is `20 * n`, where `n` is the number of modules.
    ///                 Returns an empty bytes array if the first slot is not set.
    function enumerateModules() external view returns (bytes memory modules) {
        for (uint8 i; i < type(uint8).max; i++) {
            address module = getModule(i);

            if (module == address(0)) break;

            modules = abi.encodePacked(modules, module);
        }
    }

    ///////////////////////////////////////////////////////////////
    // --- EXECUTION
    ///////////////////////////////////////////////////////////////

    /// @notice Executes a batch of delegate calls to registered modules.
    /// @dev Each element in the `calls` array must be encoded as:
    ///      - 1 byte: the module identifier (`uint8`), corresponding to a registered module.
    ///      - N bytes: Optional ABI-encoded call data using `abi.encodeWithSelector(...)`, where:
    ///         - The first 4 bytes represent the function selector.
    ///         - The remaining bytes (a multiple of 32) represent the function arguments.
    ///
    ///      Example: `bytes.concat(bytes1(identifier), abi.encodeWithSelector(...))`
    ///
    ///      All calls are performed using `delegatecall`, so state changes affect this contract.
    /// @param calls An array of encoded calls. Each call must start with a 1-byte module identifier
    ///              followed by the ABI-encoded function call data.
    /// @return returnData An array containing the returned data for each call, in order.
    /// @custom:throws OwnableUnauthorizedAccount if the caller is not the owner
    /// @custom:throws ModuleNotSet if the module for a given identifier is not set
    /// @custom:throws _ if a `calls[i]` element is empty
    function execute(bytes[] calldata calls) external payable returns (bytes[] memory) {
        bytes[] memory returnData = new bytes[](calls.length);

        for (uint256 i; i < calls.length; i++) {
            address module = getModule(uint8(calls[i][0]));
            require(module != address(0), ModuleNotSet(uint8(calls[i][0])));

            // `calls[i][1:]` is the optional calldata, including the function selector, w/o the module identifier
            returnData[i] = Address.functionDelegateCall(module, calls[i][1:]);
        }

        return returnData;
    }
}
