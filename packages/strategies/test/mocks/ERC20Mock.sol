// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "forge-std/src/mocks/MockERC20.sol";

contract ERC20Mock is MockERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        initialize(name_, symbol_, decimals_);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}
