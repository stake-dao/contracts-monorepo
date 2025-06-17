// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";
import {ArrayHelpers} from "test/common/utils/helpers/ArrayHelpers.sol";
import {TokenHelpers} from "test/common/utils/helpers/TokenHelpers.sol";

abstract contract BaseTest is Test, ArrayHelpers, TokenHelpers {
    using stdStorage for StdStorage;

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    //////////////////////////////////////////////////////////////////////////*/
    /// @notice Utility function to ensure a fuzzed address has not been previously labeled
    function _assumeUnlabeledAddress(address fuzzedAddress) internal view {
        vm.assume(bytes10(bytes(vm.getLabel(fuzzedAddress))) == bytes10(bytes("unlabeled:")));
    }

    /// @notice Helper to deploy code to a specific address (for harness contracts)
    function _deployHarnessCode(string memory artifactPath, bytes memory constructorArgs, address target) internal {
        deployCodeTo(artifactPath, constructorArgs, target);
    }

    /// @notice Helper to deploy code to a specific address (for harness contracts)
    function _deployHarnessCode(string memory artifactPath, address target) internal {
        deployCodeTo(artifactPath, target);
    }

    /// @notice Helper to override a storage slot by hand. Useful for overriding mappings
    /// @param target The target contract address
    /// @param signature The signature of the function to override
    /// @param value The value to set the storage slot to
    /// @param key The key of the storage slot to override
    function _cheat_override_storage(address target, string memory signature, bytes32 value, bytes32 key) internal {
        stdstore.target(target).sig(signature).with_key(key).checked_write(value);
    }

    /// @notice Helper to override a storage slot by hand. Useful for overriding non-mapping storage slots
    /// @param target The target contract address
    /// @param signature The signature of the function to override
    /// @param value The value to set the storage slot to
    function _cheat_override_storage(address target, string memory signature, bytes32 value) internal {
        stdstore.target(target).sig(signature).checked_write(value);
    }
}
