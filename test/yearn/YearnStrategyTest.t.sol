// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Vm.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";
import {YearnStrategy} from "src/yearn/strategy/YearnStrategy.sol";
import {StrategyVault} from "src/base/vault/StrategyVault.sol";

contract YearnStrategyTest is Test {

    YearnStrategy public strategy;
    StrategyVault public vault;
    address public locker;
    address public veToken;
    address public dYFI;
    address public sdYFI;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("ethereum"));
        vm.selectFork(forkId);

        locker = AddressBook.YFI_LOCKER;
        veToken = AddressBook.VE_YFI;
        sdYFI = AddressBook.SD_YFI;

        strategy = new YearnStrategy(address(this), locker, veToken, dYFI, sdYFI);
    }
}