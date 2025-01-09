// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IRegistry} from "src/interfaces/IRegistry.sol";

contract MockRegistry is IRegistry {
    address public vault;

    function vaults(address) external view returns (address) {
        return vault;
    }

    function setVault(address _vault) external {
        vault = _vault;
    }
}
