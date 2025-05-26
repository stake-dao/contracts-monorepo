// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {BaseTest} from "test/Base.t.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {YieldnestProtocol} from "address-book/src/YieldnestEthereum.sol";

contract AutocompoundedVaultTest is BaseTest {
    ProtocolController internal protocolController;

    function setUp() public virtual override {
        super.setUp();

        // Deploy a mock version of the sdYND token at the expected address
        vm.etch(YieldnestProtocol.SDYND, address(new MockERC20()).code);
        MockERC20(YieldnestProtocol.SDYND).initialize("sdYND", "sdYND", 18);
        vm.label(YieldnestProtocol.SDYND, "sdYND");

        // Deploy the protocol controller
        protocolController = new ProtocolController();
        vm.label(address(protocolController), "ProtocolController");
    }

    function _cheat_mockAllowed(bool allowed) internal {
        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(protocolController.allowed.selector),
            abi.encode(allowed)
        );
    }
}
