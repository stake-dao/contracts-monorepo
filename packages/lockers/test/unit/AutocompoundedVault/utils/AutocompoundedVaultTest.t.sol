// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {YieldnestLocker} from "@address-book/src/YieldnestEthereum.sol";
import {YieldnestAutocompoundedVault} from "src/integrations/yieldnest/YieldnestAutocompoundedVault.sol";

contract AutocompoundedVaultTest is Test {
    address internal owner = address(this);

    YieldnestAutocompoundedVault internal autocompoundedVault;

    function setUp() public virtual {
        // Deploy a mock version of the sdYND token at the expected address
        vm.etch(YieldnestLocker.SDYND, address(new MockERC20()).code);
        MockERC20(YieldnestLocker.SDYND).initialize("sdYND", "sdYND", 18);
        vm.label(YieldnestLocker.SDYND, "sdYND");

        // Deploy the Yieldnest Autocompounded Vault
        autocompoundedVault = new YieldnestAutocompoundedVault(owner);
        vm.label(address(autocompoundedVault), "YieldnestAutocompoundedVault");

        // Label the owner
        vm.label(owner, "owner");
    }
}
