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
import {PancakeVaultFactoryXChain} from "src/cake/factory/PancakeVaultFactoryXChain.sol";
import {Constants} from "src/base/utils/Constants.sol";

contract PancakeERC20StrategyTest is Test {
    using FixedPointMathLib for uint256;

    // WBNB/CAKE LP wrap
    address public constant CAKE_V2_WRAP = 0x047Ad4AFCFfE502B6BC021c5621e694ABB491396;

    PancakeVaultFactoryXChain public factory;

    PancakeERC20Strategy public strategy;
    PancakeERC20Strategy public strategyImpl;
    Vault public vaultImpl;

    Vault vault;
    ILiquidityGaugeStrat rewardDistributor;

    ILocker public locker;
    address public veToken;

    address public gaugeImpl;

    IExecutor public constant EXECUTOR = IExecutor(CAKE.EXECUTOR);

    address public constant claimer = address(0xBEEC);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("bnb"));

        /// Initialize from the address book.
        locker = ILocker(CAKE.LOCKER);

        /// Deploy Strategy.
        strategyImpl = new PancakeERC20Strategy(
            address(this), address(locker), address(0), CAKE.TOKEN, address(0), address(EXECUTOR)
        );

        address strategyProxy = LibClone.deployERC1967(address(strategyImpl));

        strategy = PancakeERC20Strategy(payable(strategyProxy));
        strategy.initialize(address(this));

        /// Deploy Vault Implentation.
        vaultImpl = new Vault();

        // Deploy gauge Implementation
        gaugeImpl = deployBytecode(Constants.LGV4_STRAT_XCHAIN_BYTECODE, "");

        /// Deploy Factory.
        factory = new PancakeVaultFactoryXChain(address(strategy), address(vaultImpl), gaugeImpl, CAKE.TOKEN);

        /// Setup Strategy.
        strategy.setFactory(address(factory));
        strategy.setAccumulator(address(0xACC)); // Fake accumulator.
        strategy.setFeeRewardToken(CAKE.TOKEN);

        strategy.updateProtocolFee(1_700); // 17%
        strategy.updateClaimIncentiveFee(100); // 1%

        /// Setup Locker.
        vm.prank(DAO.GOVERNANCE);
        EXECUTOR.allowAddress(address(strategy));

        /// Create vault and reward distributor for gauge.
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

        /// Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        ERC20 token = vault.token();

        // Wrap token balance
        ICakeV2Wrapper.UserInfo memory userInfo = ICakeV2Wrapper(CAKE_V2_WRAP).userInfo(address(locker));
        assertEq(userInfo.amount, amount);

        /// Token Balances.
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);

        /// Strategy Balances.
        //assertEq(strategy.balanceOf(address(token)), amount);

        /// User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(rewardDistributor.balanceOf(address(this)), amount);
    }

    function test_withdraw() public {
        uint256 amount = 100e18;

        deal(address(vault.token()), address(this), amount);
        vault.token().approve(address(vault), amount);

        /// Deposit with _doEarn = true.
        vault.deposit(address(this), amount, true);

        /// Withdraw.
        vault.withdraw(amount);

        ERC20 token = vault.token();

        /// Token Balances.
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(address(this)), amount);

        /// Strategy Balances.
        //assertEq(strategy.balanceOf(address(token)), 0);

        // Wrap token balance
        ICakeV2Wrapper.UserInfo memory userInfo = ICakeV2Wrapper(CAKE_V2_WRAP).userInfo(address(locker));
        assertEq(userInfo.amount, 0);

        /// User balances.
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(rewardDistributor.balanceOf(address(this)), 0);
    }

    function test_harvest(uint128 _amount) public {}

    function deployBytecode(bytes memory bytecode, bytes memory args) private returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }
}
