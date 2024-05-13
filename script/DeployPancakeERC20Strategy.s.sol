// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "solady/utils/LibClone.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "address-book/dao/56.sol";
import "address-book/lockers/56.sol";

import "src/base/utils/Constants.sol";

import "src/cake/adapter/DEdgeAdapter.sol";
import "src/cake/adapter/AlpacaAdapter.sol";
import "src/cake/adapter/AdapterFactory.sol";
import "src/cake/adapter/AdapterRegistry.sol";

import "src/cake/vault/ALMDepositorVault.sol";
import "src/cake/strategy/PancakeERC20Strategy.sol";
import "src/cake/factory/PancakeVaultFactoryXChain.sol";

contract DeployPancakeERC20Strategy is Script, Test {
    address public constant DEPLOYER = DAO.MAIN_DEPLOYER;
    address public constant GOVERNANCE = DAO.GOVERNANCE;

    ALMDepositorVault public vault;
    ALMDepositorVault public vaultImpl;

    PancakeERC20Strategy public strategy;
    PancakeERC20Strategy public strategyImpl;

    address public rewardDistributorImpl;
    ILiquidityGaugeStrat public rewardDistributor;

    PancakeVaultFactoryXChain public factory;

    AdapterFactory public adapterFactory;
    AdapterRegistry public adapterRegistry;

    DEdgeAdapter public dEdgeAdapterImpl;
    AlpacaAdapter public alpacaAdapterImpl;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        // Deploy Strategy.
        strategyImpl =
            new PancakeERC20Strategy(GOVERNANCE, CAKE.LOCKER, address(0), CAKE.TOKEN, address(0), CAKE.EXECUTOR);

        address strategyProxy = address(new ERC1967Proxy(address(strategyImpl), ""));

        strategy = PancakeERC20Strategy(payable(strategyProxy));
        strategy.initialize(DEPLOYER);

        // Deploy Vault Implentation.
        vaultImpl = new ALMDepositorVault();

        // Deploy gauge Implementation
        rewardDistributorImpl = deployBytecode(Constants.LGV4_STRAT_XCHAIN_BYTECODE, "");

        /// Deploy Adapter Registry
        adapterRegistry = new AdapterRegistry();
        adapterRegistry.setAllowed(DEPLOYER, true);

        // Deploy Factory.
        factory = new PancakeVaultFactoryXChain(
            address(strategy), address(vaultImpl), rewardDistributorImpl, address(CAKE.TOKEN), address(adapterRegistry)
        );

        // Setup Strategy.
        strategy.setFactory(address(factory));
        strategy.setFeeRewardToken(address(CAKE.TOKEN));

        strategy.updateProtocolFee(1_700); // 17%
        strategy.updateClaimIncentiveFee(100); // 1%

        /// Setup Adapter Factory.
        adapterFactory = new AdapterFactory(address(adapterRegistry), address(strategy));

        /// Deploy Adapter Implementations.
        dEdgeAdapterImpl = new DEdgeAdapter();
        alpacaAdapterImpl = new AlpacaAdapter();

        /// Register Protocol Adapters.
        adapterFactory.setAdapterImplementation("DeFiEdge", address(dEdgeAdapterImpl));
        adapterFactory.setAdapterImplementation("Alpaca Finance", address(alpacaAdapterImpl));

        /// Allow Factory to register adapters.
        adapterRegistry.setAllowed(address(adapterFactory), true);

        strategy.transferGovernance(GOVERNANCE);
        adapterRegistry.transferGovernance(GOVERNANCE);
        adapterFactory.transferGovernance(GOVERNANCE);

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
