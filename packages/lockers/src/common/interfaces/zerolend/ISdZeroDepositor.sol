// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IDepositor} from "src/common/interfaces/IDepositor.sol";

interface ISdZeroDepositor is IDepositor {
    function joinStakeDaoLocker(uint256[] calldata _tokenIds) external;
}
