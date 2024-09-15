// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import {MultiCumulativeMerkleDrop} from "src/common/MultiCumulativeMerkleDrop.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

contract MockMultiCumulativeMerkleDrop is MultiCumulativeMerkleDrop {
    constructor(address _governance) MultiCumulativeMerkleDrop(_governance) {}

    function name() external pure override returns (string memory) {
        return "TestMultiCumulativeMerkleDrop";
    }

    function version() external pure override returns (string memory) {
        return "1.0.0";
    }
}

contract MockERC20 is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
