// SPDX-License-Identifier: GPL3
pragma solidity 0.8.19;

// Base Tests
import "forge-std/Test.sol";

import {BalancerStrategy} from "src/balancer/strategy/BalancerStrategy.sol";
import {BalancerVault} from "src/balancer/vault/BalancerVault.sol";
import {IBalancerAccumulator} from "src/base/interfaces/IBalancerAccumulator.sol";
import "src/base/external/TransparentUpgradeableProxy.sol";
import {Constants} from "herdaddy/utils/Constants.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {DAO} from "address-book/dao/1.sol";
import {BAL} from "address-book/lockers/1.sol";

interface IVault {
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }
}

interface IBalancerHelper {
    function queryJoin(bytes32 poolId, address sender, address recipient, IVault.JoinPoolRequest memory request)
        external
        returns (uint256 bptOut, uint256[] memory amountsIn);
}

contract BalancerVaultTest is Test {
    address public constant STETH_STABLE_POOL = 0x32296969Ef14EB0c6d29669C550D4a0449130230;
    address public constant OHM_DAI_WETH_POOL = 0xc45D42f801105e861e86658648e3678aD7aa70f9;
    address public constant STRATEGY = 0x873b031Ea6E4236E44d933Aae5a66AF6d4DA419d;
    address public constant LOCAL_DEPLOYER = address(0xDE);
    address public constant ALICE = address(0xAA);

    bytes32 public constant STETH_STABLE_POOL_ID = 0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;
    bytes32 public constant OHM_DAI_WETH_POOL_ID = 0xc45d42f801105e861e86658648e3678ad7aa70f900010000000000000000011e;

    address public constant OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant BALANCER_HELPER = 0x5aDDCCa35b7A0D07C74063c48700C8590E87864E;

    IBalancerHelper public helper;
    ILiquidityGaugeStrat public liquidityGaugeImpl;
    ILiquidityGaugeStrat public liquidityGauge;
    ILiquidityGaugeStrat public weightedPoolLiquidityGauge;
    address internal proxyAdmin = address(0xABCD);
    IBalancerAccumulator public accumulator;
    BalancerStrategy public strategy;
    BalancerVault public vault;
    BalancerVault public weightedPoolVault;
    TransparentUpgradeableProxy internal proxy;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 17006312);
        vm.selectFork(forkId);

        vm.startPrank(LOCAL_DEPLOYER);
        //proxyAdmin = new ProxyAdmin();
        helper = IBalancerHelper(BALANCER_HELPER);
        accumulator = IBalancerAccumulator(ILocker(BAL.LOCKER).accumulator());
        strategy = new BalancerStrategy(
            ILocker(BAL.LOCKER), LOCAL_DEPLOYER, LOCAL_DEPLOYER, accumulator, LOCAL_DEPLOYER, LOCAL_DEPLOYER
        );
        vault = new BalancerVault();
        weightedPoolVault = new BalancerVault();
        vault.init(ERC20Upgradeable(STETH_STABLE_POOL), LOCAL_DEPLOYER, "vaultToken", "vaultToken", strategy);
        weightedPoolVault.init(
            ERC20Upgradeable(OHM_DAI_WETH_POOL), LOCAL_DEPLOYER, "vaultToken", "vaultToken", strategy
        );

        liquidityGaugeImpl = ILiquidityGaugeStrat(deployBytecode(Constants.LGV4_STRAT_BYTECODE, ""));

        // Deploy Liquidity Gauge V4
        bytes memory lgData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,string)",
            address(vault),
            LOCAL_DEPLOYER,
            DAO.SDT,
            DAO.VESDT,
            DAO.VESDT_BOOST_PROXY,
            LOCAL_DEPLOYER,
            address(vault),
            "gauge"
        );
        proxy = new TransparentUpgradeableProxy(address(liquidityGaugeImpl), proxyAdmin, lgData);
        liquidityGauge = ILiquidityGaugeStrat(address(proxy));

        // Deploy Liquidity Gauge V4 for wieghted vault
        lgData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,string)",
            address(weightedPoolVault),
            LOCAL_DEPLOYER,
            DAO.SDT,
            DAO.VESDT,
            DAO.VESDT_BOOST_PROXY,
            LOCAL_DEPLOYER,
            address(weightedPoolVault),
            "gauge"
        );
        proxy = new TransparentUpgradeableProxy(address(liquidityGaugeImpl), proxyAdmin, lgData);
        weightedPoolLiquidityGauge = ILiquidityGaugeStrat(address(proxy));

        vault.setLiquidityGauge(address(liquidityGauge));
        weightedPoolVault.setLiquidityGauge(address(weightedPoolLiquidityGauge));
        vm.stopPrank();

        deal(WSTETH, LOCAL_DEPLOYER, 1_000e18);
        deal(WETH, LOCAL_DEPLOYER, 1_000e18);
        deal(DAI, LOCAL_DEPLOYER, 1_000e18);
        deal(OHM, LOCAL_DEPLOYER, 1_000e18);
    }

    function testDepositWithUnderlyingToken() public {
        vm.startPrank(LOCAL_DEPLOYER);
        ERC20(WSTETH).approve(address(vault), type(uint256).max);
        ERC20(WETH).approve(address(vault), type(uint256).max);
        address[] memory array1 = new address[](2);
        uint256[] memory array2 = new uint256[](2);
        array1[0] = address(WSTETH);
        array1[1] = address(WETH);
        array2[0] = 1e18;
        array2[1] = 1e18;
        (uint256 bptOut,) = IBalancerHelper(BALANCER_HELPER).queryJoin(
            STETH_STABLE_POOL_ID,
            LOCAL_DEPLOYER,
            LOCAL_DEPLOYER,
            IVault.JoinPoolRequest(array1, array2, abi.encode(1, array2, 1e18), false)
        );

        vault.provideLiquidityAndDeposit(LOCAL_DEPLOYER, array2, false, bptOut);

        uint256 keeperCut = (bptOut * 10) / 10000;
        uint256 expectedLiquidityGaugeTokenAmount = bptOut - keeperCut;
        uint256 lpBalanceAfter = ERC20(STETH_STABLE_POOL).balanceOf(address(vault));
        uint256 gaugeTokenBalanceAfter = liquidityGauge.balanceOf(LOCAL_DEPLOYER);
        uint256 wETHBalanceOfVault = ERC20(WETH).balanceOf(address(vault));
        uint256 wstETHBalanceOfVault = ERC20(WSTETH).balanceOf(address(vault));

        assertEq(lpBalanceAfter, bptOut, "ERROR_010");
        assertEq(gaugeTokenBalanceAfter, expectedLiquidityGaugeTokenAmount, "ERROR_011");
        assertEq(wETHBalanceOfVault, 0, "ERROR_012");
        assertEq(wstETHBalanceOfVault, 0, "ERROR_013");
    }

    function testDepositWithUnderlyingTokenToWeightedPool() public {
        vm.startPrank(LOCAL_DEPLOYER);
        ERC20(OHM).approve(address(weightedPoolVault), type(uint256).max);
        ERC20(DAI).approve(address(weightedPoolVault), type(uint256).max);
        ERC20(WETH).approve(address(weightedPoolVault), type(uint256).max);
        address[] memory array1 = new address[](3);
        uint256[] memory array2 = new uint256[](3);
        array1[0] = address(OHM);
        array1[1] = address(DAI);
        array1[2] = address(WETH);
        array2[0] = 10e18;
        array2[1] = 170e18;
        array2[2] = 1e18;
        (uint256 bptOut,) = IBalancerHelper(BALANCER_HELPER).queryJoin(
            OHM_DAI_WETH_POOL_ID,
            LOCAL_DEPLOYER,
            LOCAL_DEPLOYER,
            IVault.JoinPoolRequest(array1, array2, abi.encode(1, array2, 1e18), false)
        );
        weightedPoolVault.provideLiquidityAndDeposit(LOCAL_DEPLOYER, array2, false, bptOut);
        vm.stopPrank();

        uint256 keeperCut = (bptOut * 10) / 10000;
        uint256 expectedLiquidityGaugeTokenAmount = bptOut - keeperCut;
        uint256 gaugeTokenBalanceAfter = weightedPoolLiquidityGauge.balanceOf(LOCAL_DEPLOYER);

        uint256 lpBalanceAfter = ERC20(OHM_DAI_WETH_POOL).balanceOf(address(weightedPoolVault));
        uint256 wETHBalanceOfVault = ERC20(WETH).balanceOf(address(weightedPoolVault));
        uint256 daiBalanceOfVault = ERC20(DAI).balanceOf(address(weightedPoolVault));
        uint256 ohmBalanceOfVault = ERC20(OHM).balanceOf(address(weightedPoolVault));

        assertEq(lpBalanceAfter, bptOut, "ERROR_020");
        assertEq(gaugeTokenBalanceAfter, expectedLiquidityGaugeTokenAmount, "ERROR_021");
        assertEq(wETHBalanceOfVault, 0, "ERROR_022");
        assertEq(daiBalanceOfVault, 0, "ERROR_023");
        assertEq(ohmBalanceOfVault, 0, "ERROR_023");
    }

    function testDepositWithSingleUnderlyingToken() public {
        vm.startPrank(LOCAL_DEPLOYER);
        ERC20(OHM).approve(address(weightedPoolVault), type(uint256).max);
        address[] memory array1 = new address[](3);
        uint256[] memory array2 = new uint256[](3);
        array1[0] = address(OHM);
        array1[1] = address(DAI);
        array1[2] = address(WETH);
        array2[0] = 10e18;
        array2[1] = 0;
        array2[2] = 0;
        (uint256 bptOut,) = IBalancerHelper(BALANCER_HELPER).queryJoin(
            OHM_DAI_WETH_POOL_ID,
            LOCAL_DEPLOYER,
            LOCAL_DEPLOYER,
            IVault.JoinPoolRequest(array1, array2, abi.encode(1, array2, 1e18), false)
        );
        weightedPoolVault.provideLiquidityAndDeposit(LOCAL_DEPLOYER, array2, false, bptOut);
        vm.stopPrank();

        uint256 lpBalanceAfter = ERC20(OHM_DAI_WETH_POOL).balanceOf(address(weightedPoolVault));
        uint256 ohmBalanceOfVault = ERC20(OHM).balanceOf(address(weightedPoolVault));

        assertEq(ohmBalanceOfVault, 0, "ERROR_030");
        assertEq(lpBalanceAfter, bptOut, "ERROR_031");
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) internal returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }
}
