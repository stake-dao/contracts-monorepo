// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "forge-std/Vm.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";

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
    VyperDeployer vyperDeployer = new VyperDeployer();

    // External Contracts
    IRewardPool internal rewardPool = IRewardPool(AddressBook.YFI_REWARD_POOL);
    YearnLocker internal yearnLocker;

    // Liquid Lockers Contracts
    IERC20 internal YFI = IERC20(AddressBook.YFI);
    IVeYFI internal veYFI = IVeYFI(AddressBook.VE_YFI);
    sdToken internal sdYFI;

    DepositorV2 internal depositor;
    ILiquidityGauge internal liquidityGauge;
    YearnAccumulator internal yearnAccumulator;

    // Helper
    uint256 internal constant amount = 100e18;

    function setUp() public {
        sdYFI = new sdToken("Stake DAO YFI", "sdYFI");

        address liquidityGaugeImpl = vyperDeployer.deployContract("src/base/staking/LiquidityGaugeV4.vy");

        // Deploy LiquidityGauge
        liquidityGauge = ILiquidityGauge(
            address(
                new TransparentUpgradeableProxy(
                liquidityGaugeImpl,
                AddressBook.PROXY_ADMIN,
                abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(sdYFI),
                address(this),
                AddressBook.SDT,
                AddressBook.VE_SDT,
                AddressBook.VE_SDT_BOOST_PROXY,
                AddressBook.SDT_DISTRIBUTOR
                )
                )
            )
        );

        // Deploy and Intialize the YearnLocker contract
        yearnLocker = new YearnLocker(address(this), address(this), address(veYFI), address(rewardPool));
        yearnLocker.approveUnderlying();

        // Deploy Depositor Contract
        depositor = new DepositorV2(AddressBook.YFI, address(yearnLocker), address(sdYFI), 4*365 days);
        depositor.setGauge(address(liquidityGauge));
        sdYFI.setOperator(address(depositor));
        yearnLocker.setYFIDepositor(address(depositor));

        // Deploy Accumulator Contract
        yearnAccumulator = new YearnAccumulator(address(AddressBook.YFI), address(liquidityGauge));
        yearnAccumulator.setLocker(address(yearnLocker));
        yearnLocker.setAccumulator(address(yearnAccumulator));

        // Add Reward to LGV4
        liquidityGauge.add_reward(AddressBook.YFI, address(yearnAccumulator));

        // Mint YFI to the adresss(this)
        deal(address(YFI), address(yearnLocker), amount);

        yearnLocker.createLock(amount, block.timestamp + 4 * 365 days);

        // Mint YFI to the adresss(this)
        deal(address(YFI), address(this), amount);
    }

    function testInitialStateDepositor() public {
        uint256 end = veYFI.locked(address(yearnLocker)).end;
        assertEq(end, depositor.unlockTime());
    }

    function testDepositThroughtDepositor() public {
        // Deposit YFI to the YearnLocker through the Depositor
        YFI.approve(address(depositor), amount);
        depositor.deposit(amount, true, false, address(this));

        assertEq(sdYFI.balanceOf(address(this)), amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);
    }

    function testDepositThroughtDepositorWithStake() public {
        // Deposit YFI to the YearnLocker through the Depositor
        YFI.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(liquidityGauge.balanceOf(address(this)), amount);
    }

    function testDepositorIncreaseTime() public {
        // Deposit YFI to the YearnLocker through the Depositor
        YFI.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(liquidityGauge.balanceOf(address(this)), amount);
        uint256 oldEnd = veYFI.locked(address(yearnLocker)).end;
        // Increase Time
        vm.warp(block.timestamp + 2 weeks);
        uint256 newExpectedEnd = (block.timestamp + 4 * 365 days) / 1 weeks * 1 weeks;

        deal(address(YFI), address(this), amount);
        YFI.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        uint256 end = veYFI.locked(address(yearnLocker)).end;

        assertGt(end, oldEnd);
        assertEq(end, newExpectedEnd);
        assertEq(liquidityGauge.balanceOf(address(this)), 2 * amount);
    }

    function testAccumulatorRewards() public {
        // Fill the Reward Pool with YFI.
        deal(address(YFI), address(rewardPool), amount);

        vm.warp(block.timestamp + 2 weeks);
        rewardPool.checkpoint_token();

        assertEq(YFI.balanceOf(address(liquidityGauge)), 0);
        yearnAccumulator.claimAndNotifyAll();
        assertGt(YFI.balanceOf(address(liquidityGauge)), 0);
    }
}
