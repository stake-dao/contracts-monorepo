// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Vm.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import {AddressBook} from "addressBook/AddressBook.sol";
import {YearnStrategy} from "src/yearn/strategy/YearnStrategy.sol";
import {StrategyVaultImpl} from "src/base/vault/StrategyVaultImpl.sol";
import {YearnVaultFactory} from "src/yearn/factory/YearnVaultFactory.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";

interface ICurvePool {
    function exchange_underlying(uint256, uint256, uint256, uint256) external payable;
}

interface IDyfiOption {
    function eth_required(uint256) external view returns(uint256);
    function redeem(uint256) external payable;
}

contract YearnStrategyTest is Test {
    YearnVaultFactory public factory;
    YearnStrategy public strategy;
    StrategyVaultImpl public vaultImpl;
    ILocker public locker;
    address public veToken;
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant LOCKER_GOV = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public sdYFI;
    address public sdtDistributor;

    address[] public yearnGauges = [
        0x81d93531720d86f0491DeE7D03f30b3b5aC24e59, // yETh
        0x7Fd8Af959B54A677a1D8F92265Bd0714274C56a3, // YFI-ETH
        0x107717C98C8125A94D3d2Cc82b86a1b705f3A27C, // yCRV
        0x28da6dE3e804bDdF0aD237CFA6048f2930D0b4Dc // dYFIETH
    ];

    address[] public yearnLps = new address[](yearnGauges.length);
    address[] public sdVaults = new address[](yearnGauges.length);
    address[] public sdGauges = new address[](yearnGauges.length);

    address public constant DYFIETH_POOL = 0x8aC64Ba8E440cE5c2d08688f4020698b1826152E;
    address public constant DYFI_OPTION = 0x2fBa208E1B2106d40DaA472Cb7AE0c6C7EFc0224;

    address public constant GAUGE_IMPL = 0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("ethereum"));
        vm.selectFork(forkId);

        locker = ILocker(AddressBook.YFI_LOCKER);
        veToken = AddressBook.VE_YFI;
        sdYFI = AddressBook.SD_YFI;
        sdtDistributor = AddressBook.SDT_DISTRIBUTOR_STRAT;
        strategy = new YearnStrategy(address(this), address(locker), veToken, DYFI, sdYFI);

        vaultImpl = new StrategyVaultImpl();
        factory = new YearnVaultFactory(address(strategy), address(vaultImpl), GAUGE_IMPL);

        strategy.setFactory(address(factory));
        vm.prank(LOCKER_GOV);
        locker.setGovernance(address(strategy));

        for (uint256 i; i < yearnGauges.length - 1; i++) {
            vm.recordLogs();
            factory.create(yearnGauges[i]);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            assertEq(entries.length, 11);
            assertEq(entries[8].topics[0], keccak256("PoolDeployed(address,address,address,address)"));
            (sdVaults[i],sdGauges[i],,) = abi.decode(entries[8].data, (address,address,address,address));
        }

        for (uint256 i; i < yearnGauges.length; i++) {
            yearnLps[i] = ILiquidityGaugeStrat(yearnGauges[i]).asset();
            deal(yearnLps[i], address(this), 1e18);
        }
        deal(address(this), 3e18);
    }

    function testCloneVault() external {
        vm.recordLogs();
        factory.create(yearnGauges[3]);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 11);
        assertEq(entries[8].topics[0], keccak256("PoolDeployed(address,address,address,address)"));
        (address vault,,,) = abi.decode(entries[8].data, (address,address,address,address));
        
        string memory name = StrategyVaultImpl(vault).name();
        string memory symbol = StrategyVaultImpl(vault).symbol(); 
        assertEq(name, "sdyvCurve-dYFIETH-f-f Vault");
        assertEq(symbol, "sdyvCurve-dYFIETH-f-f-vault");
    }

    function testVaultInteraction() external {
        uint256 amountToDeposit = 1e17;
        uint256 vaultBalance;
        uint256 gaugeBalance;
        for (uint256 i; i < sdVaults.length - 1; i++) {
            IERC20(yearnLps[i]).approve(sdVaults[i], amountToDeposit);
            StrategyVaultImpl(sdVaults[i]).deposit(address(this), amountToDeposit, true);
            vaultBalance = IERC20(yearnLps[i]).balanceOf(sdVaults[i]);
            gaugeBalance = IERC20(sdVaults[i]).balanceOf(sdGauges[i]);
            assertEq(vaultBalance, 0);
            assertEq(gaugeBalance, amountToDeposit);
        }
    }

    // function testReedem() external {
    //     // buy dYFI on curve
    //     ICurvePool(DYFIETH_POOL).exchange_underlying{value:5e17}(1, 0, 5e17, 0);
    //     emit log_uint(IERC20(DYFI).balanceOf(address(this)));
    //     uint256 dYfiBalance = IERC20(DYFI).balanceOf(address(this));
    //     uint256 ethRequired = IDyfiOption(DYFI_OPTION).eth_required(dYfiBalance);
    //     IERC20(DYFI).approve(DYFI_OPTION, 1000e18);
    //     IDyfiOption(DYFI_OPTION).redeem{value:ethRequired}(dYfiBalance);
    //     uint256 yearnBalance = IERC20(AddressBook.YFI).balanceOf(address(this));
    //     emit
    // }
}
