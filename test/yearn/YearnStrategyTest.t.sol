// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "solady/utils/LibClone.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import {AddressBook} from "addressBook/AddressBook.sol";
import {YearnStrategy} from "src/yearn/strategy/YearnStrategy.sol";
import {YearnStrategyVaultImpl} from "src/yearn/vault/YearnStrategyVaultImpl.sol";
import {YearnVaultFactoryOwnable} from "src/yearn/factory/YearnVaultFactoryOwnable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {IYearnRewardPool} from "src/base/interfaces/IYearnRewardPool.sol";

interface ICurvePool {
    function exchange_underlying(uint256, uint256, uint256, uint256) external payable;
}

interface IDyfiOption {
    function eth_required(uint256) external view returns (uint256);
    function redeem(uint256) external payable;
}

contract YearnStrategyTest is Test {
    YearnVaultFactoryOwnable public factory;
    YearnStrategy public strategy;
    YearnStrategy public strategyImpl;
    YearnStrategyVaultImpl public vaultImpl;
    ILocker public locker;
    address public veToken;
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;
    address public constant DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
    address public constant LOCKER_GOV = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public sdYFI;
    address public sdtDistributor;
    address public yfi;

    address[] public yearnGauges = [
        0x81d93531720d86f0491DeE7D03f30b3b5aC24e59, // yETh
        0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3, // YFI-ETH
        0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C, // yCRV
        0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc // dYFIETH
    ];

    address[] public yearnLps = new address[](yearnGauges.length);
    address[] public sdVaults = new address[](yearnGauges.length);
    address[] public sdGauges = new address[](yearnGauges.length);

    address public constant GAUGE_IMPL = 0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9;
    address public constant YEARN_ACC = 0x8b65438178CD4EF67b0177135dE84Fe7E3C30ec3;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("ethereum"), 18431190);
        vm.selectFork(forkId);

        locker = ILocker(AddressBook.YFI_LOCKER);
        veToken = AddressBook.VE_YFI;
        sdYFI = AddressBook.SD_YFI;
        yfi = AddressBook.YFI;
        sdtDistributor = AddressBook.SDT_DISTRIBUTOR_STRAT;
        strategyImpl = new YearnStrategy(address(this), address(locker), veToken, DYFI, sdYFI);
        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));
        strategy = YearnStrategy(payable(strategyProxy));
        strategy.initialize(address(this));

        vaultImpl = new YearnStrategyVaultImpl();
        factory = new YearnVaultFactoryOwnable(address(strategy), address(vaultImpl), GAUGE_IMPL);

        strategy.setFactory(address(factory));
        strategy.setAccumulator(YEARN_ACC);
        strategy.setFeeRewardToken(yfi);
        vm.prank(LOCKER_GOV);
        locker.setGovernance(address(strategy));

        for (uint256 i; i < yearnGauges.length - 1; i++) {
            vm.recordLogs();
            factory.create(yearnGauges[i]);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            assertEq(entries.length, 11);
            assertEq(entries[7].topics[0], keccak256("PoolDeployed(address,address,address,address)"));
            (sdVaults[i], sdGauges[i],,) = abi.decode(entries[7].data, (address, address, address, address));
        }

        for (uint256 i; i < yearnGauges.length; i++) {
            yearnLps[i] = ILiquidityGaugeStrat(yearnGauges[i]).asset();
            deal(yearnLps[i], address(this), 1e17);
        }
        deal(address(this), 3e18);
        deal(yearnGauges[0], address(this), 1e18);
    }

    function testCloneVault() external {
        vm.recordLogs();
        factory.create(yearnGauges[3]);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 11);
        assertEq(entries[7].topics[0], keccak256("PoolDeployed(address,address,address,address)"));
        (address vault,,,) = abi.decode(entries[7].data, (address, address, address, address));

        string memory name = YearnStrategyVaultImpl(vault).name();
        string memory symbol = YearnStrategyVaultImpl(vault).symbol();
        assertEq(name, "sdyvCurve-dYFIETH-f-f Vault");
        assertEq(symbol, "sdyvCurve-dYFIETH-f-f-vault");
    }

    function testVaultInteraction() external {
        uint256 amountToDeposit = 1e17;
        uint256 vaultBalance;
        uint256 gaugeBalance;
        uint256 userBalance;
        for (uint256 i; i < sdVaults.length - 1; i++) {
            IERC20(yearnLps[i]).approve(sdVaults[i], amountToDeposit);
            YearnStrategyVaultImpl(sdVaults[i]).deposit(address(this), amountToDeposit, true);
            vaultBalance = IERC20(yearnLps[i]).balanceOf(sdVaults[i]);
            gaugeBalance = IERC20(sdVaults[i]).balanceOf(sdGauges[i]);
            assertEq(vaultBalance, 0);
            assertEq(gaugeBalance, amountToDeposit);
            // skip 1 second
            skip(10 seconds);
            YearnStrategyVaultImpl(sdVaults[i]).withdraw(amountToDeposit);
            userBalance = IERC20(yearnLps[i]).balanceOf(address(this));
            gaugeBalance = IERC20(sdVaults[i]).balanceOf(sdGauges[i]);
            assertEq(userBalance, amountToDeposit);
            assertEq(gaugeBalance, 0);
        }
    }

    function testGaugeTokenDeposit() external {
        uint256 amountToDeposit = 1e18;
        IERC20(yearnGauges[0]).approve(sdVaults[0], amountToDeposit);
        assertEq(IERC20(sdGauges[0]).balanceOf(address(this)), 0);
        assertEq(IERC20(yearnGauges[0]).balanceOf(address(locker)), 0);
        YearnStrategyVaultImpl(sdVaults[0]).depositGaugeToken(address(this), amountToDeposit);
        assertEq(IERC20(sdGauges[0]).balanceOf(address(this)), amountToDeposit);
        assertEq(IERC20(yearnGauges[0]).balanceOf(address(locker)), amountToDeposit);
    }

    function testHarvest() external {
        uint256 amountToDeposit = 1e17;
        IERC20(yearnLps[0]).approve(sdVaults[0], amountToDeposit);
        YearnStrategyVaultImpl(sdVaults[0]).deposit(address(this), amountToDeposit, true);
        skip(1 days);
        uint256 gaugeRewardBalance = IERC20(DYFI).balanceOf(sdGauges[0]);
        assertEq(gaugeRewardBalance, 0);
        strategy.harvest(yearnLps[0], false, false);
        gaugeRewardBalance = IERC20(DYFI).balanceOf(sdGauges[0]);
        assertGt(gaugeRewardBalance, 0);
        skip(1 days);
        uint256 userRewardBalance = IERC20(DYFI).balanceOf(address(this));
        assertEq(userRewardBalance, 0);
        ILiquidityGaugeStrat(sdGauges[0]).claim_rewards(address(this));
        userRewardBalance = IERC20(DYFI).balanceOf(address(this));
        assertGt(userRewardBalance, 0);
    }

    function testClaimNativeRewards() external {
        IYearnRewardPool(YFI_REWARD_POOL).checkpoint_token();
        IYearnRewardPool(YFI_REWARD_POOL).checkpoint_total_supply();
        uint256 accRewardBalance = IERC20(yfi).balanceOf(YEARN_ACC);
        assertEq(accRewardBalance, 0);
        strategy.claimNativeRewards();
        accRewardBalance = IERC20(yfi).balanceOf(YEARN_ACC);
        assertGt(accRewardBalance, 0);
    }

    function testClaimDyfiRewards() external {
        IYearnRewardPool(DYFI_REWARD_POOL).checkpoint_token();
        IYearnRewardPool(DYFI_REWARD_POOL).checkpoint_total_supply();
        uint256 accRewardBalance = IERC20(DYFI).balanceOf(YEARN_ACC);
        assertEq(accRewardBalance, 0);
        strategy.claimDYfiRewardPool();
        accRewardBalance = IERC20(DYFI).balanceOf(YEARN_ACC);
        assertGt(accRewardBalance, 0);
    }
}
