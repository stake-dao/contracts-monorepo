// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "test/base/Strategy.t.sol";
import "solady/utils/LibClone.sol";

import {AddressBook} from "addressBook/AddressBook.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {YearnStrategy} from "src/yearn/strategy/YearnStrategy.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {YearnStrategyVaultImpl} from "src/yearn/vault/YearnStrategyVaultImpl.sol";
import {YearnVaultFactoryOwnable} from "src/yearn/factory/YearnVaultFactoryOwnable.sol";

abstract contract YearnStrategyTestBis is StrategyTest {
    address public immutable gauge;

    YearnVaultFactoryOwnable public factory;

    YearnStrategy public strategy;
    YearnStrategy public strategyImpl;
    YearnStrategyVaultImpl public vaultImpl;

    YearnStrategyVaultImpl vault;
    ILiquidityGaugeStrat rewardDistributor;

    ILocker public locker;
    address public veToken;
    address public sdtDistributor;

    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;
    address public constant DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;

    address public constant GAUGE_IMPL = 0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9;

    constructor(address _gauge) {
        gauge = _gauge;
    }

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 18_472_574);

        /// Initialize from the address book.
        veToken = AddressBook.VE_YFI;
        locker = ILocker(AddressBook.YFI_LOCKER);
        sdtDistributor = AddressBook.SDT_DISTRIBUTOR;

        /// Deploy Strategy.
        strategyImpl = new YearnStrategy(address(this), address(locker), veToken, DYFI, YFI_REWARD_POOL);

        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));

        strategy = YearnStrategy(payable(strategyProxy));
        strategy.initialize(address(this));

        /// Deploy Vault Implentation.
        vaultImpl = new YearnStrategyVaultImpl();

        /// Deploy Factory.
        factory = new YearnVaultFactoryOwnable(address(strategy), address(vaultImpl), GAUGE_IMPL);

        /// Setup Strategy.
        strategy.setFactory(address(factory));
        strategy.setAccumulator(address(0xACC)); // Fake accumulator.
        strategy.setFeeRewardToken(AddressBook.YFI);

        /// Setup Locker.
        vm.prank(locker.governance());
        locker.setGovernance(address(strategy));

        /// Create vault and reward distributor for gauge.
        address _vault;
        address _rewardDistributor;
        (_vault, _rewardDistributor) = factory.create(gauge);

        vault = YearnStrategyVaultImpl(_vault);
        rewardDistributor = ILiquidityGaugeStrat(_rewardDistributor);
    }

    function test_deposit(uint128 _amount) public testDeposit(vault, strategy, _amount) {
        uint256 amount = uint256(_amount);
        vm.assume(amount != 0);

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        /// Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);
    }
}
