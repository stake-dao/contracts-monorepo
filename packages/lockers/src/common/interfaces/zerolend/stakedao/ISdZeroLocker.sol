// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ILocker} from "src/common/interfaces/ILocker.sol";

interface ISdZeroLocker is ILocker {
    error NotDepositor();
    error NotOwnerOfToken(uint256 tokenId);
    error EmptyTokenIdList();

    function zeroLockedTokenId() external returns (uint256);

    function deposit(address _owner, uint256[] calldata _tokenIds) external returns (uint256);

    function release(address _recipient) external;
}
