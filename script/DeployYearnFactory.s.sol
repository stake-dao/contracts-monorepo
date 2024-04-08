// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {YearnVaultFactory} from "src/yearn/factory/YearnVaultFactory.sol";

contract DeployYearnFactory is Script, Test {
    address public constant STRATEGY = 0x1be150a35bb8233d092747eBFDc75FB357c35168;
    address public constant VAULT_IMPL = 0x210DfEc4Fc0c3B88E7984a86Dc315f43AA07A68a;
    address public constant GAUGE_IMPL = 0xc1e4775B3A589784aAcD15265AC39D3B3c13Ca3c;

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        // Deploy Vault factory
        new YearnVaultFactory(address(STRATEGY), address(VAULT_IMPL), address(GAUGE_IMPL));

        vm.stopBroadcast();
    }
}
