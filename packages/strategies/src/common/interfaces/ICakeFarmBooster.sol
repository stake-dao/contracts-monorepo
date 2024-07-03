// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

interface ICakeFarmBooster {
    function whiteListWrapper(address _wrapper) external view returns (bool);
}
