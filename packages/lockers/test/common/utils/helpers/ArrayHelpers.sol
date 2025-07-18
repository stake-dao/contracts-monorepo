// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

abstract contract ArrayHelpers {
    function erase(address[] memory arr, address value) internal pure {
        uint256 keepCnt = 0;
        for (uint256 i = 0; i < arr.length; ++i) {
            if (arr[i] == value) continue;
            arr[keepCnt++] = arr[i];
        }
        assembly ("memory-safe") {
            mstore(arr, keepCnt)
        }
    }

    function toArray(address a) internal pure returns (address[] memory res) {
        res = new address[](1);
        res[0] = a;
    }

    function toArray(address a, address b) internal pure returns (address[] memory res) {
        res = new address[](2);
        res[0] = a;
        res[1] = b;
    }

    function toArray(bool a) internal pure returns (bool[] memory res) {
        res = new bool[](1);
        res[0] = a;
    }
}
