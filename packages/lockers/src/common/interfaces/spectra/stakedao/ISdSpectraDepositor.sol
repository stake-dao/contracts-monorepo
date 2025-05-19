// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IDepositor} from "src/common/interfaces/IDepositor.sol";

interface ISdSpectraDepositor is IDepositor {
    error ZeroValue();
    error GOVERNANCE();
    error EmptyTokenIdList();
    error LockAlreadyExists();
    error AccumulatorNotSet();
    error ExecFromSafeModuleFailed();
    error NotOwnerOfToken(uint256 tokenId);

    function deposit(uint256[] calldata _tokenIds, bool _stake, address _user) external;

    function spectraLockedTokenId() external view returns (uint256 spectraLockedTokenId);

    function mintRewards() external;

    function setAccumulator(address _accumulator) external;

    function accumulator() external view returns (address);
}
