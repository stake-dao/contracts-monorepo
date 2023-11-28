// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

library Utils {
    error DEPLOYMENT_FAILED();

    function deployBytecode(bytes memory bytecode, bytes memory args) public returns (address deployed) {
        if (args.length > 0) {
            bytecode = abi.encodePacked(bytecode, args);
        }

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        if (deployed == address(0)) revert DEPLOYMENT_FAILED();
    }
}
