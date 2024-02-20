// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "test/base/BaseTest.t.sol";

import {ILocker} from "src/base/interfaces/ILocker.sol";
import {AngleVaultFactory} from "src/angle/factory/AngleVaultFactory.sol";
import {AngleVault} from "src/angle/vault/AngleVault.sol";
import {AngleStrategy} from "src/angle/strategy/AngleStrategy.sol";
import {IAccumulator} from "src/base/interfaces/IAccumulator.sol";
//import {IveSDTFeeProxy} from "src/base/interfaces/IveSDTFeeProxy.sol";
import {ISdtDistributorV2} from "src/base/interfaces/ISdtDistributorV2.sol";
import {AngleVaultGUni} from "src/angle/vault/AngleVaultGUni.sol";
import {TransparentUpgradeableProxy} from "src/base/external/TransparentUpgradeableProxy.sol";

import {IMc} from "src/base/interfaces/IMc.sol";
import {ISmartWalletChecker} from "src/base/interfaces/ISmartWalletChecker.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {IGaugeController} from "src/base/interfaces/IGaugeController.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import {Angle, Frax} from "address-book/protocols/1.sol";
import {DAO} from "address-book/dao/1.sol";

import {Constants} from "herdaddy/utils/Constants.sol";

contract AngleVaultTest is BaseTest {
    address public constant BOB = address(0xB0B);
    address public constant ALICE = address(0xAA);
    address public constant LOCAL_DEPLOYER = address(0xDE);
    address public constant GUNI_AGEUR_WETH_LP = 0x857E0B2eD0E82D5cDEB015E77ebB873C47F99575;
    address public constant GUNI_AGEUR_WETH_ANGLE_GAUGE = 0x3785Ce82be62a342052b9E5431e9D3a839cfB581;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant SDFRAX3CRV = 0x5af15DA84A4a6EDf2d9FA6720De921E1026E37b7;

    uint256 public constant AMOUNT = 1_000e18;

    AngleVault public vaultUSDC;
    AngleVault public vaultDAI;
    address public proxyAdmin;
    AngleStrategy public strategy;
    AngleVaultGUni public vaultGUNI;
    ISdtDistributorV2 public distributor;
    ISdtDistributorV2 public distributorImpl;
    AngleVaultFactory public factory;
    address public feeProxy;
    TransparentUpgradeableProxy public proxy;

    ILocker public locker = ILocker(0xD13F8C25CceD32cdfA79EB5eD654Ce3e484dCAF5);
    IAccumulator public accumulator = IAccumulator(0x943671e6c3A98E28ABdBc60a7ac703b3c0C6aA51);

    IGaugeController public gaugeController;
    ILiquidityGaugeStrat public liquidityGaugeDAI;
    ILiquidityGaugeStrat public liquidityGaugeUSDC;
    ILiquidityGaugeStrat public liquidityGaugeGUNI;
    ILiquidityGaugeStrat public liquidityGaugeStratImpl;

    IERC20 public guni = IERC20(GUNI_AGEUR_WETH_LP);
    IERC20 public sandaieur = IERC20(Angle.SAN_DAI_EUR);
    IERC20 public sanusdceur = IERC20(Angle.SAN_USDC_EUR);

    IMc public masterChef = IMc(0xfEA5E213bbD81A8a94D0E1eDB09dBD7CEab61e1c);
    ILiquidityGaugeStrat public gaugeSdAngle = ILiquidityGaugeStrat(0xE55843a90672f7d8218285e51EE8fF8E233F35d5);
    ILiquidityGaugeStrat public gaugeGUniEur = ILiquidityGaugeStrat(0x3785Ce82be62a342052b9E5431e9D3a839cfB581);
    ILiquidityGaugeStrat public liquidityGaugeAngleGUNI = ILiquidityGaugeStrat(GUNI_AGEUR_WETH_ANGLE_GAUGE);
    ILiquidityGaugeStrat public liquidityGaugeAngleDAI =
        ILiquidityGaugeStrat(0x8E2c0CbDa6bA7B65dbcA333798A3949B07638026);
    ILiquidityGaugeStrat public liquidityGaugeAngleUSDC =
        ILiquidityGaugeStrat(0x51fE22abAF4a26631b2913E417c0560D547797a7);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 16798050);
        vm.selectFork(forkId);

        address[] memory path = new address[](3);
        path[0] = Angle.ANGLE;
        path[1] = WETH;
        path[2] = Frax.FRAX;

        vm.startPrank(LOCAL_DEPLOYER);
        //feeProxy = new veSDTFeeAngleProxy(path);
        //proxyAdmin = new ProxyAdmin();
        //distributorImpl = new SdtDistributorV2();
        gaugeController = IGaugeController(
            deployBytecode(Constants.GAUGE_CONTROLLER_BYTECODE, abi.encode(DAO.SDT, DAO.VESDT, LOCAL_DEPLOYER))
        );
        // gaugeController = IGaugeController(
        //     deployCode(
        //         "artifacts/vyper-contracts/GaugeController.vy/GaugeController.json",
        //         abi.encode(DAO.SDT, DAO.VESDT, LOCAL_DEPLOYER)
        //     )
        // );
        liquidityGaugeStratImpl = ILiquidityGaugeStrat(deployBytecode(Constants.LGV4_STRAT_BYTECODE, ""));
        // liquidityGaugeStratImpl = ILiquidityGaugeStrat(
        //     deployCode("artifacts/vyper-contracts/LiquidityGaugeV4Strat.vy/LiquidityGaugeV4Strat.json")
        // );
        // bytes memory distributorData = abi.encodeWithSignature(
        //     "initialize(address,address,address,address)",
        //     address(gaugeController),
        //     LOCAL_DEPLOYER,
        //     LOCAL_DEPLOYER,
        //     LOCAL_DEPLOYER
        // );
        // proxy = new TransparentUpgradeableProxy(address(distributorImpl), proxyAdmin, distributorData);
        // distributor = ISdtDistributorV2(address(proxy));
        strategy = new AngleStrategy(
            ILocker(address(locker)),
            LOCAL_DEPLOYER,
            LOCAL_DEPLOYER,
            IAccumulator(address(0)),
            feeProxy,
            address(distributor)
        );
        strategy.setAccumulator(address(accumulator));
        factory = new AngleVaultFactory(address(liquidityGaugeStratImpl), address(strategy), address(distributor));
        strategy.setVaultGaugeFactory(address(factory));

        // Clone and Init
        vm.recordLogs();
        factory.cloneAndInit(address(liquidityGaugeAngleUSDC));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes memory eventData1 = logs[0].data;
        bytes memory eventData3 = logs[2].data;
        vaultUSDC = AngleVault(bytesToAddressCustom(eventData1, 32));
        liquidityGaugeUSDC = ILiquidityGaugeStrat(bytesToAddressCustom(eventData3, 32));

        // Add gauge type
        gaugeController.add_type("Mainnet staking", 1e18); // 0
        gaugeController.add_type("External", 1e18); // 1
        gaugeController.add_type("Cross Chain", 1e18); // 2
        gaugeController.add_gauge(address(liquidityGaugeUSDC), 0, 0);
        vm.stopPrank();

        // Masterchef <> SdtDistributor setup
        IERC20 masterToken = IERC20(distributor.masterchefToken());
        vm.prank(masterChef.owner());
        masterChef.add(1000, address(masterToken), false);

        vm.startPrank(LOCAL_DEPLOYER);
        distributor.initializeMasterchef(masterChef.poolLength() - 1);
        distributor.setDistribution(true);
        vaultGUNI = new AngleVaultGUni(
            ERC20(GUNI_AGEUR_WETH_LP),
            LOCAL_DEPLOYER,
            "Stake DAO GUniAgeur/ETH Vault",
            "sdGUniAgeur/ETH-vault",
            strategy,
            966923637982619002
        );
        bytes memory lgData = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,string)",
            address(vaultGUNI),
            LOCAL_DEPLOYER,
            DAO.SDT,
            DAO.VESDT,
            DAO.VESDT_BOOST_PROXY, // to mock
            address(strategy),
            address(vaultGUNI),
            "agEur/ETH"
        );
        proxy = new TransparentUpgradeableProxy(address(liquidityGaugeStratImpl), proxyAdmin, lgData);
        liquidityGaugeGUNI = ILiquidityGaugeStrat(address(proxy));
        vaultGUNI.setLiquidityGauge(address(liquidityGaugeGUNI));
        strategy.toggleVault(address(vaultGUNI));
        strategy.setGauge(GUNI_AGEUR_WETH_LP, GUNI_AGEUR_WETH_ANGLE_GAUGE);
        strategy.setMultiGauge(GUNI_AGEUR_WETH_ANGLE_GAUGE, address(liquidityGaugeGUNI));
        vm.stopPrank();

        vm.prank(locker.governance());
        locker.setGovernance(address(strategy));

        vm.prank(IveToken(DAO.VESDT).admin());
        ISmartWalletChecker(DAO.SMART_WALLET_CHECKER).approveWallet(LOCAL_DEPLOYER);

        deal(Angle.SAN_USDC_EUR, LOCAL_DEPLOYER, AMOUNT * 100);
        deal(Angle.SAN_DAI_EUR, LOCAL_DEPLOYER, AMOUNT * 100);
        deal(DAO.SDT, LOCAL_DEPLOYER, AMOUNT * 100);
        deal(GUNI_AGEUR_WETH_LP, LOCAL_DEPLOYER, AMOUNT * 100);
        lockSDTCustom(LOCAL_DEPLOYER, DAO.SDT, DAO.VESDT, AMOUNT, block.timestamp + (4 * 365 days));

        vm.startPrank(LOCAL_DEPLOYER);
        sanusdceur.approve(address(vaultUSDC), type(uint256).max);
        guni.approve(address(vaultGUNI), type(uint256).max);
        vm.stopPrank();
    }

    function test01LGSettings() public {
        assertEq(liquidityGaugeUSDC.name(), "Stake DAO sanUSDC_EUR Gauge");
        assertEq(liquidityGaugeUSDC.symbol(), "sdsanUSDC_EUR-gauge");
    }

    function test02DepositSanUSDCToVault() public {
        vm.prank(LOCAL_DEPLOYER);
        vaultUSDC.deposit(LOCAL_DEPLOYER, AMOUNT, false);
        assertEq(sanusdceur.balanceOf(address(vaultUSDC)), AMOUNT);
        assertEq(liquidityGaugeUSDC.balanceOf(LOCAL_DEPLOYER), (AMOUNT * 999) / 1000);
    }

    function test03WithdrawFromVault() public {
        vm.startPrank(LOCAL_DEPLOYER);
        vaultUSDC.deposit(LOCAL_DEPLOYER, AMOUNT, false);
        vaultUSDC.withdraw(liquidityGaugeUSDC.balanceOf(LOCAL_DEPLOYER));
        vm.stopPrank();
        assertEq(sanusdceur.balanceOf(address(vaultUSDC)), (AMOUNT * 1) / 1000);
        assertEq(liquidityGaugeUSDC.balanceOf(LOCAL_DEPLOYER), 0);
    }

    function test04WithdrawRevert() public {
        vm.startPrank(LOCAL_DEPLOYER);
        vaultUSDC.deposit(LOCAL_DEPLOYER, AMOUNT, false);
        uint256 balanceBefore = liquidityGaugeUSDC.balanceOf(LOCAL_DEPLOYER);
        liquidityGaugeUSDC.transfer(ALICE, AMOUNT / 2);
        vm.expectRevert(bytes("Not enough staked"));
        vaultUSDC.withdraw(balanceBefore);
        vm.stopPrank();
    }

    function test05WithdrawRevert() public {
        vm.expectRevert();
        liquidityGaugeUSDC.withdraw(AMOUNT, ALICE);
    }

    function test06ApproveVaultRevert() public {
        vm.expectRevert("!governance && !factory");
        strategy.toggleVault(address(vaultUSDC));
    }

    function test07AddGaugeRevert() public {
        vm.expectRevert("!governance && !factory");
        strategy.setGauge(address(sanusdceur), address(liquidityGaugeAngleUSDC));
    }

    function test08GetAccumulatedFee() public {
        vm.prank(LOCAL_DEPLOYER);
        vaultUSDC.deposit(LOCAL_DEPLOYER, AMOUNT, false);
        uint256 accumulatedFee = vaultUSDC.accumulatedFee();
        vm.prank(ALICE);
        vaultUSDC.deposit(ALICE, 0, true);
        assertGt(liquidityGaugeAngleUSDC.balanceOf(address(locker)), AMOUNT);
        assertEq(sanusdceur.balanceOf(address(vaultUSDC)), 0);
        assertEq(liquidityGaugeUSDC.balanceOf(ALICE), accumulatedFee);
    }

    function test09ClaimReward() public {
        vm.startPrank(LOCAL_DEPLOYER);
        distributor.approveGauge(address(liquidityGaugeUSDC));
        gaugeController.vote_for_gauge_weights(address(liquidityGaugeUSDC), 10000);
        vaultUSDC.deposit(LOCAL_DEPLOYER, AMOUNT, true);
        skip(30 days);

        uint256 claimable = liquidityGaugeAngleUSDC.claimable_reward(address(locker), Angle.ANGLE);
        uint256 balanceBeforeAccumulator = IERC20(Angle.ANGLE).balanceOf(address(accumulator));

        vm.recordLogs();
        strategy.claim(address(sanusdceur));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 claimed = sliceUint(logs[logs.length - 1].data, 2 * 32);

        assertGt(claimed, 0);
        assertEq(claimable, claimed);
        assertGt(liquidityGaugeUSDC.reward_data(Angle.ANGLE).rate, 0);
        assertGt(liquidityGaugeUSDC.reward_data(DAO.SDT).rate, 0);
        assertEq(gaugeController.gauge_relative_weight(address(liquidityGaugeUSDC)), 1e18);
        assertEq(
            IERC20(Angle.ANGLE).balanceOf(address(accumulator)) - balanceBeforeAccumulator, (claimed * 800) / 10_000
        );
    }

    function test10GetMaxBoost() public {
        vm.prank(LOCAL_DEPLOYER);
        vaultUSDC.deposit(LOCAL_DEPLOYER, AMOUNT, true);
        uint256 workingBalance = liquidityGaugeAngleUSDC.working_balances(address(locker));
        uint256 stakedAmount = liquidityGaugeAngleUSDC.balanceOf(address(locker));
        uint256 boost = (workingBalance * 10e18) / (stakedAmount * 4);
        assertApproxEqRel(boost, 25e17, 40e16); // ± 40% due to the uge amount of veANGLE owned by LL
    }

    // function test11UseFeeDistributor() public {
    //     deal(DAO.ANGLE, address(feeProxy), 10_000e18);
    //     uint256 balanceBeforeClaimer = IERC20(Frax.FRAX).balanceOf(LOCAL_DEPLOYER);
    //     uint256 balanceBeforeFeeDist = IERC20(SDFRAX3CRV).balanceOf(DAO.FEE_DISTRIBUTOR);
    //     vm.prank(LOCAL_DEPLOYER);
    //     feeProxy.sendRewards();
    //     uint256 balanceAfterClaimer = IERC20(Frax.FRAX).balanceOf(LOCAL_DEPLOYER);
    //     uint256 balanceAfterFeeDist = IERC20(SDFRAX3CRV).balanceOf(DAO.FEE_DISTRIBUTOR);

    //     assertGt(balanceAfterClaimer, balanceBeforeClaimer);
    //     assertGt(balanceAfterFeeDist, balanceBeforeFeeDist);
    // }

    function test12AccumulateAngleRewardToSdAngle() public {
        uint256 balanceBeforeAngleGauge = IERC20(Angle.ANGLE).balanceOf(address(gaugeSdAngle));

        vm.prank(gaugeSdAngle.admin());
        gaugeSdAngle.set_reward_distributor(Angle.ANGLE, address(accumulator));

        deal(Angle.ANGLE, address(accumulator), AMOUNT);
        vm.startPrank(accumulator.governance());
        accumulator.setGauge(address(gaugeSdAngle));
        accumulator.notifyAllExtraReward(Angle.ANGLE);
        uint256 balanceAfterAngleGauge = IERC20(Angle.ANGLE).balanceOf(address(gaugeSdAngle));
        uint256 balanceAfterAccumulato = IERC20(Angle.ANGLE).balanceOf(address(accumulator));

        assertGt(balanceAfterAngleGauge, balanceBeforeAngleGauge);
        assertEq(balanceAfterAccumulato, 0);
    }

    function test13CreateNewVault() public {
        vm.startPrank(LOCAL_DEPLOYER);
        // Clone and Init
        vm.recordLogs();
        factory.cloneAndInit(address(liquidityGaugeAngleDAI));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes memory eventData1 = logs[0].data;
        bytes memory eventData3 = logs[2].data;
        vaultDAI = AngleVault(bytesToAddressCustom(eventData1, 32));
        liquidityGaugeDAI = ILiquidityGaugeStrat(bytesToAddressCustom(eventData3, 32));
        gaugeController.add_gauge(address(liquidityGaugeDAI), 0, 0);
        distributor.approveGauge(address(liquidityGaugeDAI));
        vm.stopPrank();
        assertEq(address(vaultDAI.token()), Angle.SAN_DAI_EUR);
    }

    function test14DepositToNewVault() public {
        test13CreateNewVault();
        vm.startPrank(LOCAL_DEPLOYER);
        sandaieur.approve(address(vaultDAI), type(uint256).max);
        vaultDAI.deposit(LOCAL_DEPLOYER, AMOUNT, false);
        vm.stopPrank();
        assertEq(sandaieur.balanceOf(address(vaultDAI)), AMOUNT);
        assertEq(liquidityGaugeDAI.balanceOf(LOCAL_DEPLOYER), (AMOUNT * 999) / 1000);
    }

    function test15CallEarn() public {
        uint256 balanceBefore = liquidityGaugeAngleDAI.balanceOf(address(locker));
        test14DepositToNewVault();
        vm.prank(ALICE);
        vaultDAI.deposit(ALICE, 0, true);
        assertEq(liquidityGaugeAngleDAI.balanceOf(address(locker)) - balanceBefore, AMOUNT);
    }

    // It should distribute for one gauge for during 44 days then it should distribute other gauge rewards at once for 44days
    function test16DistributeRewardsFor2Gauge() public {
        test15CallEarn();
        vm.startPrank(LOCAL_DEPLOYER);
        distributor.approveGauge(address(liquidityGaugeUSDC));
        gaugeController.vote_for_gauge_weights(address(liquidityGaugeUSDC), 5000);
        gaugeController.vote_for_gauge_weights(address(liquidityGaugeDAI), 5000);
        vm.stopPrank();
        skip(8 days);
        vm.prank(0x4f91F01cE8ec07c9B1f6a82c18811848254917Ab); // Angle depositor
        liquidityGaugeAngleDAI.deposit_reward_token(Angle.ANGLE, AMOUNT);
        vm.prank(LOCAL_DEPLOYER);
        strategy.claim(address(sandaieur));

        for (uint8 i; i < 44; ++i) {
            skip(1 days);
            vm.prank(LOCAL_DEPLOYER);
            strategy.claim(address(sandaieur));
            if (i % 7 == 0) {
                vm.prank(0x4f91F01cE8ec07c9B1f6a82c18811848254917Ab); // Angle depositor
                liquidityGaugeAngleDAI.deposit_reward_token(Angle.ANGLE, AMOUNT);
                vm.prank(0x4f91F01cE8ec07c9B1f6a82c18811848254917Ab); // Angle depositor
                liquidityGaugeAngleUSDC.deposit_reward_token(Angle.ANGLE, AMOUNT);
            }
        }
        vm.prank(LOCAL_DEPLOYER);
        strategy.claim(address(sanusdceur));
        assertEq(IERC20(DAO.SDT).balanceOf(address(distributor)), 0);
    }

    function test17StakeGUNIToken() public {
        uint256 balanceBefore = liquidityGaugeAngleGUNI.balanceOf(address(locker));
        vm.prank(LOCAL_DEPLOYER);
        vaultGUNI.deposit(LOCAL_DEPLOYER, AMOUNT, true);
        uint256 balanceAfter = liquidityGaugeAngleGUNI.balanceOf(address(locker));
        uint256 scalingFactor = vaultGUNI.scalingFactor();
        uint256 scaledDown = (AMOUNT * scalingFactor) / (1e18);
        assertEq(balanceAfter - balanceBefore, scaledDown);
    }

    function test18WithdrawAll() public {
        test17StakeGUNIToken();
        uint256 balanceBefore = liquidityGaugeGUNI.balanceOf(LOCAL_DEPLOYER);
        vm.prank(LOCAL_DEPLOYER);
        vaultGUNI.withdraw(balanceBefore);
        uint256 balanceAfter = liquidityGaugeGUNI.balanceOf(LOCAL_DEPLOYER);

        assertGt(balanceBefore, 0);
        assertLt(balanceAfter, 10);
    }

    function test19WithdrawPartially() public {
        uint256 before = liquidityGaugeAngleGUNI.balanceOf(address(locker));
        vm.startPrank(LOCAL_DEPLOYER);
        vaultGUNI.deposit(LOCAL_DEPLOYER, AMOUNT, true);
        vaultGUNI.deposit(LOCAL_DEPLOYER, AMOUNT, false);
        uint256 balanceBeforeGauge = liquidityGaugeAngleGUNI.balanceOf(address(locker));
        uint256 balanceBefore = liquidityGaugeGUNI.balanceOf(LOCAL_DEPLOYER);
        vaultGUNI.withdraw(balanceBefore);
        uint256 balanceAfter = liquidityGaugeGUNI.balanceOf(LOCAL_DEPLOYER);
        uint256 balanceAfterGauge = liquidityGaugeAngleGUNI.balanceOf(address(locker));
        uint256 scalingFactor = vaultGUNI.scalingFactor();
        uint256 scaledDown = (AMOUNT * scalingFactor) / (1e18);
        assertGt(balanceBefore, 0);
        assertLt(balanceAfter, 10);
        assertEq(balanceAfterGauge - before, 0);
        assertEq(balanceBeforeGauge - before, scaledDown);
    }
}
