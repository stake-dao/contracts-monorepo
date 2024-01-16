// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "forge-std/Vm.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";

import "test/utils/Utils.sol";
import {Constants} from "src/base/utils/Constants.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {YearnLocker} from "src/yearn/locker/YearnLocker.sol";

import {IVeYFI} from "src/base/interfaces/IVeYFI.sol";
import {IRewardPool} from "src/base/interfaces/IRewardPool.sol";

import {DepositorV2} from "src/base/depositor/DepositorV2.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {YearnAccumulator} from "src/yearn/accumulator/YearnAccumulator.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract YearnIntegrationTest is Test {
    // External Contracts
    IRewardPool internal rewardPool = IRewardPool(Yearn.YFI_REWARD_POOL);
    YearnLocker internal yearnLocker;

    // Liquid Lockers Contracts
    IERC20 internal _YFI = IERC20(YFI.TOKEN);
    IVeYFI internal veYFI = IVeYFI(Yearn.VEYFI);
    sdToken internal sdYFI;

    DepositorV2 internal depositor;
    ILiquidityGauge internal liquidityGauge;
    YearnAccumulator internal yearnAccumulator;

    // Helper
    uint256 internal constant amount = 100e18;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
        sdYFI = new sdToken("Stake DAO YFI", "sdYFI");

        address liquidityGaugeImpl = Utils.deployBytecode(Constants.LGV4_BYTECODE, "");

        // Deploy LiquidityGauge
        liquidityGauge = ILiquidityGauge(
            address(
                new TransparentUpgradeableProxy(
                    liquidityGaugeImpl,
                    DAO.PROXY_ADMIN,
                    abi.encodeWithSignature(
                        "initialize(address,address,address,address,address,address)",
                        address(sdYFI),
                        address(this),
                        DAO.SDT,
                        DAO.VESDT,
                        DAO.VESDT_BOOST_PROXY,
                        DAO.LOCKER_SDT_DISTRIBUTOR
                    )
                )
            )
        );

        // Deploy and Intialize the YearnLocker contract
        yearnLocker = new YearnLocker(address(this), address(this), address(veYFI), address(rewardPool));
        yearnLocker.approveUnderlying();

        // Deploy Depositor Contract
        depositor = new DepositorV2(YFI.TOKEN, address(yearnLocker), address(sdYFI), 4 * 365 days);
        depositor.setGauge(address(liquidityGauge));
        sdYFI.setOperator(address(depositor));
        yearnLocker.setYFIDepositor(address(depositor));

        // Deploy Accumulator Contract
        yearnAccumulator = new YearnAccumulator(address(YFI.TOKEN), address(liquidityGauge));
        yearnAccumulator.setLocker(address(yearnLocker));
        yearnLocker.setAccumulator(address(yearnAccumulator));

        // Add Reward to LGV4
        liquidityGauge.add_reward(YFI.TOKEN, address(yearnAccumulator));

        // Mint YFI to the adresss(this)
        deal(address(_YFI), address(yearnLocker), amount);

        yearnLocker.createLock(amount, block.timestamp + 4 * 365 days);

        // Mint YFI to the adresss(this)
        deal(address(_YFI), address(this), amount);
    }

    function testInitialStateDepositor() public {
        uint256 end = veYFI.locked(address(yearnLocker)).end;
        assertEq(end, depositor.unlockTime());
    }

    function testDepositThroughtDepositor() public {
        // Deposit YFI to the YearnLocker through the Depositor
        _YFI.approve(address(depositor), amount);
        depositor.deposit(amount, true, false, address(this));

        assertEq(sdYFI.balanceOf(address(this)), amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);
    }

    function testDepositThroughtDepositorWithStake() public {
        // Deposit YFI to the YearnLocker through the Depositor
        _YFI.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(liquidityGauge.balanceOf(address(this)), amount);
    }

    function testDepositorIncreaseTime() public {
        // Deposit YFI to the YearnLocker through the Depositor
        _YFI.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(liquidityGauge.balanceOf(address(this)), amount);
        uint256 oldEnd = veYFI.locked(address(yearnLocker)).end;
        // Increase Time
        vm.warp(block.timestamp + 2 weeks);
        uint256 newExpectedEnd = (block.timestamp + 4 * 365 days) / 1 weeks * 1 weeks;

        deal(address(_YFI), address(this), amount);
        _YFI.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        uint256 end = veYFI.locked(address(yearnLocker)).end;

        assertGt(end, oldEnd);
        assertEq(end, newExpectedEnd);
        assertEq(liquidityGauge.balanceOf(address(this)), 2 * amount);
    }

    function testAccumulatorRewards() public {
        // Fill the Reward Pool with YFI.
        deal(address(_YFI), address(rewardPool), amount);

        vm.warp(block.timestamp + 2 weeks);
        rewardPool.checkpoint_token();
        rewardPool.checkpoint_total_supply();

        assertEq(_YFI.balanceOf(address(liquidityGauge)), 0);
        yearnAccumulator.claimAndNotifyAll();
        assertGt(_YFI.balanceOf(address(liquidityGauge)), 0);
    }
}
