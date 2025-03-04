// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface IStashTokenWrapper {
    function token() external view returns (address);
}