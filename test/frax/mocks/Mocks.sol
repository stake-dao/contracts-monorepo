// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ISdToken} from "src/base/interfaces/ISdToken.sol";

contract MockFxsDepositor {
    ISdToken public sdFxs;

    constructor(address _sdFxs) {
        sdFxs = ISdToken(_sdFxs);
    }

    function deposit(uint256 _amount, bool, bool, address) external {
        sdFxs.mint(msg.sender, _amount);
    }
}
