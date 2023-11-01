// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "solady/utils/LibClone.sol";
import "utils/VyperDeployer.sol";

import {AddressBook} from "addressBook/AddressBook.sol";
import {YearnStrategy} from "src/yearn/strategy/YearnStrategy.sol";
import {YearnStrategyVaultImpl} from "src/yearn/vault/YearnStrategyVaultImpl.sol";
import {YearnVaultFactoryOwnable} from "src/yearn/factory/YearnVaultFactoryOwnable.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";

contract DeployYearnStrategy is Script, Test {
    YearnStrategy public strategyImpl;
    YearnStrategy public strategy;

    YearnStrategyVaultImpl public vaultImpl;
    ILiquidityGaugeStrat public gaugeImpl;

    YearnVaultFactoryOwnable public factory;

    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant YEARN_ACC = 0x8b65438178CD4EF67b0177135dE84Fe7E3C30ec3; // v2
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    VyperDeployer public vyperDeployer = new VyperDeployer();

    function run() public {
        vm.startBroadcast(DEPLOYER);

        // Deploy strategy impl
        strategyImpl =
            new YearnStrategy(GOVERNANCE, AddressBook.YFI_LOCKER, AddressBook.VE_YFI, DYFI, AddressBook.YFI_REWARD_POOL);
        // Clone strategy
        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));
        strategy = YearnStrategy(payable(strategyProxy));
        // Initialize strategy
        strategy.initialize(DEPLOYER);

        // Deploy Vault impl
        vaultImpl = new YearnStrategyVaultImpl();

        // Deploy LGV4Strat impl
        gaugeImpl = ILiquidityGaugeStrat(vyperDeployer.deployContract("src/base/gauge/LiquidityGaugeV4Strat.vy"));

        // Deploy Vault factory
        factory = new YearnVaultFactoryOwnable(address(strategy), address(vaultImpl), address(gaugeImpl));

        // Strategy setters
        strategy.setFactory(address(factory));
        strategy.setAccumulator(YEARN_ACC);
        strategy.setFeeRewardToken(AddressBook.YFI);
        strategy.setFeeDistributor(AddressBook.YFI_REWARD_POOL);

        strategy.updateProtocolFee(1_500); // 15%
        strategy.updateClaimIncentiveFee(50); // 0.5%

        // Transfer ownership.
        strategy.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
