// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "solady/utils/LibClone.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {CAKE} from "address-book/lockers/56.sol";
import {DAO} from "address-book/dao/56.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {PancakeERC20Strategy} from "src/cake/strategy/PancakeERC20Strategy.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Vault} from "src/base/vault/Vault.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";
import {IExecutor} from "src/base/interfaces/IExecutor.sol";
import {ICakeV2Wrapper} from "src/base/interfaces/ICakeV2Wrapper.sol";
import "src/cake/factory/PancakeVaultFactoryXChain.sol";
import {Constants} from "src/base/utils/Constants.sol";

contract PancakeERC20StrategyTest is Test {
    using FixedPointMathLib for uint256;

    // WBNB/CAKE LP wrap
    address public constant CAKE_V2_WRAP = 0x1c9a562Ab4c1e45cB4C08712d18220d7cF7BA5e8;
    address public constant CAKE_V2_LP = 0x0eD7e52944161450477ee417DE9Cd3a859b14fD0;

    PancakeVaultFactoryXChain public factory;

    PancakeERC20Strategy public strategy;
    PancakeERC20Strategy public strategyImpl;
    Vault public vaultImpl;

    Vault public vault;
    ILiquidityGaugeStrat public rewardDistributor;

    ILocker public locker;
    address public veToken;

    address public gaugeImpl;

    IExecutor public constant EXECUTOR = IExecutor(CAKE.EXECUTOR);

    address public constant claimer = address(0xBEEC);

    address public constant CAKE_T = CAKE.TOKEN;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("bnb"), 37280683);

        // Initialize from the address book.
        locker = ILocker(CAKE.LOCKER);

        // Deploy Strategy.
        strategyImpl =
            new PancakeERC20Strategy(address(this), address(locker), address(0), CAKE_T, address(0), address(EXECUTOR));

        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));

        strategy = PancakeERC20Strategy(payable(strategyProxy));
        strategy.initialize(address(this));

        // Deploy Vault Implentation.
        vaultImpl = new Vault();

        // Deploy gauge Implementation
        gaugeImpl = deployBytecode(Constants.LGV4_STRAT_XCHAIN_BYTECODE, "");

        // Deploy Factory.
        factory = new PancakeVaultFactoryXChain(address(strategy), address(vaultImpl), gaugeImpl, CAKE_T);

        // Setup Strategy.
        strategy.setFactory(address(factory));
        strategy.setFeeRewardToken(CAKE_T);

        strategy.updateProtocolFee(1_700); // 17%
        strategy.updateClaimIncentiveFee(100); // 1%

        // Setup Locker.
        vm.prank(DAO.GOVERNANCE);
        EXECUTOR.allowAddress(address(strategy));

        // Create vault and reward distributor for gauge.
        address _vault;
        address _rewardDistributor;
        (_vault, _rewardDistributor) = factory.create(CAKE_V2_WRAP);

        vault = Vault(_vault);
        rewardDistributor = ILiquidityGaugeStrat(_rewardDistributor);
    }

    function test_deposit() public {
        uint256 amount = 100e18;

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        // Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        ERC20 token = vault.token();

        // Strategy balance
        assertEq(strategy.balanceOf(CAKE_V2_LP), amount);

        // Token Balances.
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);

        // User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(rewardDistributor.balanceOf(address(this)), amount);
    }

    function test_withdraw() public {
        uint256 amount = 100e18;

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        // Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        // Withdraw.
        vault.withdraw(amount);

        ERC20 token = vault.token();

        // Token Balances.
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(address(this)), amount);

        // Strategy Balances.
        assertEq(strategy.balanceOf(CAKE_V2_LP), 0);

        // User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(rewardDistributor.balanceOf(address(this)), 0);
    }

    function test_harvest() public {
        uint256 amount = 100e18;

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        // Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        skip(1 days);

        ERC20 cakeT = ERC20(CAKE_T);

        assertEq(cakeT.balanceOf(address(rewardDistributor)), 0);
        assertEq(cakeT.balanceOf(address(strategy)), 0);
        assertEq(cakeT.balanceOf(address(this)), 0);
        assertEq(strategy.feesAccrued(), 0);

        strategy.harvest(CAKE_V2_LP, false, false);

        uint256 rewardDistributorPart = cakeT.balanceOf(address(rewardDistributor));
        uint256 protocolFeePart = cakeT.balanceOf(address(strategy));
        uint256 claimerPart = cakeT.balanceOf(address(this));
        uint256 totalHarvested = rewardDistributorPart + protocolFeePart + claimerPart;
        assertGt(rewardDistributorPart, 0);
        assertGt(protocolFeePart, 0);
        assertGt(claimerPart, 0);
        assertEq(protocolFeePart, strategy.feesAccrued());

        assertEq(totalHarvested * strategy.protocolFeesPercent() / strategy.DENOMINATOR(), protocolFeePart);
        assertEq(totalHarvested * strategy.claimIncentiveFee() / strategy.DENOMINATOR(), claimerPart);
    }

    function test_create_invalid_gauge() external {
        vm.expectRevert(PoolFactoryXChain.INVALID_GAUGE.selector);
        factory.create(address(0xABCD));
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) private returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }
}
