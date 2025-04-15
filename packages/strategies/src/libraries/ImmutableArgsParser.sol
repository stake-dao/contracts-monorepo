// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title ImmutableArgsParser
/// @notice A library for reading immutable arguments from a clone.
library ImmutableArgsParser {
    /// @dev Safely read an `address` from `clone`'s immutable args at `offset`.
    function readAddress(address clone, uint256 offset) internal view returns (address result) {
        bytes memory args = Clones.fetchCloneArgs(clone);
        assembly {
            // Load 32 bytes starting at `args + offset + 32`. Then shift right
            // by 96 bits (12 bytes) so that the address is right‐aligned and
            // the high bits are cleared.
            result := shr(96, mload(add(add(args, 0x20), offset)))
        }
    }

    /// @dev Safely read a `uint256` from `clone`'s immutable args at `offset`.
    function readUint256(address clone, uint256 offset) internal view returns (uint256 result) {
        bytes memory args = Clones.fetchCloneArgs(clone);
        assembly {
            // Load the entire 32‐byte word directly.
            result := mload(add(add(args, 0x20), offset))
        }
    }
}
