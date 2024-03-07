// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ISdToken} from "src/base/interfaces/ISdToken.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockFxsDepositor {
    ISdToken public sdFxs;

    constructor(address _sdFxs) {
        sdFxs = ISdToken(_sdFxs);
    }

    function deposit(uint256 _amount, bool, bool, address) external {
        sdFxs.mint(msg.sender, _amount);
    }
}

contract MockSdFxsGauge is ERC20 {
    address public token;

    constructor(address _token) ERC20("sdFxs gauge", "sdFxs-gauge") {
        token = _token;
    }

    function deposit(uint256 _amount, address _recipient) external {
        ERC20(token).transferFrom(msg.sender, address(this), _amount);
        _mint(_recipient, _amount);
    }
}
