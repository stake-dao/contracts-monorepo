// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

interface IFraxShares {
    function owner_address() external view returns (address);
    function toggleVotes() external;
}
