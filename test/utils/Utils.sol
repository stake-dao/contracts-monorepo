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

    function deployCreate2(bytes32 salt, bytes memory bytecode) external returns (address deployed) {
        assembly {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        if (deployed == address(0)) {
            revert DEPLOYMENT_FAILED();
        }
    }

    function computeAddress(bytes32 salt, bytes32 creationCodeHash) external view returns (address addr) {
        address contractAddress = address(this);

        assembly {
            let ptr := mload(0x40)

            mstore(add(ptr, 0x40), creationCodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, contractAddress)
            let start := add(ptr, 0x0b)
            mstore8(start, 0xff)
            addr := keccak256(start, 85)
        }
    }
}
