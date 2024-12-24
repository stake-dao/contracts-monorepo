// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IFeeSplitter {
    function splitToken(address _token) external;
}
