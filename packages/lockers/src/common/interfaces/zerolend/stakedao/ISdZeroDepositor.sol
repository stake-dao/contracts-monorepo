// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDepositor} from "src/common/interfaces/IDepositor.sol";

interface ISdZeroDepositor is IDepositor {
    error ZeroValue();
    error EmptyTokenIdList();
    error NotOwnerOfToken(uint256 tokenId);
    error ExecFromSafeModuleFailed();

    function deposit(uint256[] calldata _tokenIds, bool _stake, address _user) external;
}
