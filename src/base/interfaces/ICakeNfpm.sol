// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ICakeNfpm {
    function positions(uint256)
        external
        view
        returns (uint96, address, address, address, uint24, int24, int24, uint128, uint256, uint256, uint128, uint128);
}
