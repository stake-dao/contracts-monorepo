// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IFeeSplitter {
    function split() external;
    function token() external view returns (address);
}
