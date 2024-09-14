// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

import {MultiCumulativeMerkleDrop} from "src/common/MultiCumulativeMerkleDrop.sol";

contract vlCVXMultiMerkleDrop is MultiCumulativeMerkleDrop {
    constructor(address _governance) MultiCumulativeMerkleDrop(_governance) {}

    function name() external pure override returns (string memory) {
        return "vlCVX Voters MultiMerkleDrop";
    }

    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}
