// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {PancakeMasterchefStrategy} from "src/cake/strategy/PancakeMasterchefStrategy.sol";
import {Executor} from "src/cake/utils/Executor.sol";
import {DAO} from "address-book/dao/56.sol";
import {CAKE} from "address-book/lockers/56.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployCakeStrategyNFT is Script, Test {
    PancakeMasterchefStrategy public strategyImpl;
    PancakeMasterchefStrategy public strategy;

    Executor public executor;

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = DAO.GOVERNANCE;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        // Deploy executor
        executor = new Executor(DEPLOYER);

        // Deploy strategy impl
        strategyImpl = new PancakeMasterchefStrategy(DEPLOYER, CAKE.LOCKER, CAKE.TOKEN);
        // Clone strategy
        address strategyProxy = address(new ERC1967Proxy(address(strategyImpl), ""));

        strategy = PancakeMasterchefStrategy(payable(strategyProxy));
        // Initialize strategy
        strategy.initialize(DEPLOYER, address(executor));

        assertEq(strategy.governance(), DEPLOYER);
        assertEq(address(strategy.executor()), address(executor));

        executor.allowAddress(address(strategy));

        // Strategy setters
        strategy.updateProtocolFee(1_500); // 15%

        // Transfer ownership.
        executor.transferGovernance(GOVERNANCE);
        strategy.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
