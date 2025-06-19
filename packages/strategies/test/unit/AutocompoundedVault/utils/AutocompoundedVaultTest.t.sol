// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {BaseTest} from "test/Base.t.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {YieldnestProtocol} from "@address-book/src/YieldnestEthereum.sol";
import {YieldnestAutocompoundedVault} from "src/integrations/yieldnest/YieldnestAutocompoundedVault.sol";

contract AutocompoundedVaultTest is BaseTest {
    YieldnestAutocompoundedVault internal autocompoundedVault;

    function setUp() public virtual override {
        super.setUp();

        // Deploy a mock version of the sdYND token at the expected address
        vm.etch(YieldnestProtocol.SDYND, address(new MockERC20()).code);
        MockERC20(YieldnestProtocol.SDYND).initialize("sdYND", "sdYND", 18);
        vm.label(YieldnestProtocol.SDYND, "sdYND");

        // Deploy the Yieldnest Autocompounded Vault
        autocompoundedVault = new YieldnestAutocompoundedVault(owner);
        vm.label(address(autocompoundedVault), "YieldnestAutocompoundedVault");

        // Label the owner
        vm.label(owner, "owner");
    }
}
