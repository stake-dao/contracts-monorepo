// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IFeeSplitter {
    function split() external;
    function token() external view returns (address);
}
