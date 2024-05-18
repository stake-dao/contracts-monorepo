// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {FXS} from "address-book/lockers/1.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

contract sdFXSFraxtalBridgeTest is Test {
    // address private constant DELEGATE = address(0xABCD);
    // address private constant USER = address(0xABAB);
    // address private constant TOKEN = FXS.SDTOKEN;
    // uint256 amountToSend = 1e18;
    // address private constant OFT_FRAXTAL = address(1);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
    }

    function test_bridge_to_fraxtal() public {}

    function test_bridge_to_eth() public {}
}
