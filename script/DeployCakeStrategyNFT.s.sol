// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "solady/utils/LibClone.sol";

import {CakeStrategyNFT} from "src/cake/strategy/CakeStrategyNFT.sol";
import {Executor} from "src/cake/utils/Executor.sol";
import {DAO} from "address-book/dao/56.sol";
import {CAKE} from "address-book/lockers/56.sol";

contract DeployCakeStrategyNFT is Script, Test {
    CakeStrategyNFT public strategyImpl;
    CakeStrategyNFT public strategy;

    Executor public executor;

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = DAO.GOVERNANCE;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        // Deploy executor
        executor = new Executor(DEPLOYER);

        // Deploy strategy impl
        strategyImpl = new CakeStrategyNFT(DEPLOYER, CAKE.LOCKER, CAKE.TOKEN);
        // Clone strategy
        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));
        strategy = CakeStrategyNFT(payable(strategyProxy));
        // Initialize strategy
        strategy.initialize(DEPLOYER, address(executor));

        executor.allowAddress(address(strategy));

        // Strategy setters
        strategy.updateProtocolFee(1_500); // 15%

        // Transfer ownership.
        executor.transferGovernance(GOVERNANCE);
        strategy.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
