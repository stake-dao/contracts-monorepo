// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "solady/utils/LibClone.sol";

import {CAKE} from "address-book/lockers/56.sol";
import {DAO} from "address-book/dao/56.sol";
import {PancakeERC20Strategy} from "src/cake/strategy/PancakeERC20Strategy.sol";
import {PancakeVaultFactoryXChain} from "src/cake/factory/PancakeVaultFactoryXChain.sol";
import {Vault} from "src/base/vault/Vault.sol";

import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {Constants} from "src/base/utils/Constants.sol";

contract DeployPancakeERC20Strategy is Script, Test {
    PancakeERC20Strategy public strategyImpl;
    PancakeERC20Strategy public strategy;

    Vault public vaultImpl;
    ILiquidityGaugeStrat public gaugeImpl;
    ILocker public locker;

    PancakeVaultFactoryXChain public factory;

    address public constant DEPLOYER = DAO.MAIN_DEPLOYER;
    address public constant GOVERNANCE = DAO.GOVERNANCE;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        // Initialize from the address book.
        locker = ILocker(CAKE.LOCKER);

        // Deploy Strategy.
        strategyImpl =
            new PancakeERC20Strategy(address(this), address(locker), address(0), CAKE.TOKEN, address(0), CAKE.EXECUTOR);

        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));

        strategy = PancakeERC20Strategy(payable(strategyProxy));
        strategy.initialize(address(this));

        /// Deploy Vault Implentation.
        vaultImpl = new Vault();

        // Deploy gauge Implementation
        gaugeImpl = ILiquidityGaugeStrat(deployBytecode(Constants.LGV4_STRAT_XCHAIN_BYTECODE, ""));

        // Deploy Factory.
        factory = new PancakeVaultFactoryXChain(address(strategy), address(vaultImpl), address(gaugeImpl), CAKE.TOKEN);

        // Setup Strategy.
        strategy.setFactory(address(factory));
        strategy.setFeeRewardToken(CAKE.TOKEN);

        strategy.updateProtocolFee(1_700); // 17%
        strategy.updateClaimIncentiveFee(100); // 1%

        // Transfer governance at the end
        strategy.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) private returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }
}
