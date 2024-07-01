// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import "test/utils/Utils.sol";
import {Constants} from "src/base/utils/Constants.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {PendleLocker} from "src/pendle/locker/PendleLocker.sol";
import {IVePendle} from "src/base/interfaces/IVePendle.sol";
import {PendleDepositor} from "src/pendle/depositor/PendleDepositor.sol";

import {IPendleFeeDistributor} from "src/base/interfaces/IPendleFeeDistributor.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IFraxSwapRouter} from "src/base/interfaces/IFraxSwapRouter.sol";

import {PendleAccumulator} from "src/pendle/accumulator/PendleAccumulator.sol";
import {VeSDTFeePendleProxy} from "src/pendle/ve-sdt-fee-proxy/VeSDTFeePendleProxy.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IFraxLP {
    function getAmountOut(uint256 amount, address tokenIn) external view returns (uint256);
}

contract PendleIntegrationTest is Test {
    address public constant SD_FRAX_3CRV = 0x5af15DA84A4a6EDf2d9FA6720De921E1026E37b7;

    // External Contracts
    PendleLocker internal pendleLocker;

    // Liquid Lockers Contracts
    IERC20 internal _PENDLE = IERC20(PENDLE.TOKEN);
    IVePendle internal vePENDLE = IVePendle(Pendle.VEPENDLE);
    sdToken internal sdPendle;

    PendleDepositor internal depositor;
    ILiquidityGauge internal liquidityGauge;
    PendleAccumulator internal pendleAccumulator;
    VeSDTFeePendleProxy internal veSdtFeePendleProxy;

    address public daoRecipient = makeAddr("dao");
    address public bribeRecipient = makeAddr("bribe");
    address public veSdtFeeProxy = makeAddr("feeProxy");

    // Helper
    uint128 internal constant amount = 100e18;

    uint256 public DAY = 1 days;
    uint256 public WEEK = 1 weeks;
    uint256 public YEAR = 365 days;

    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public FRAX = Frax.FRAX;

    address public constant WETH_FRAX_LP = 0x31351Bf3fba544863FBff44DDC27bA880916A199;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
        sdPendle = new sdToken("Stake DAO PENDLE", "sdPENDLE");

        address liquidityGaugeImpl = Utils.deployBytecode(Constants.LGV4_BYTECODE, "");

        // Deploy LiquidityGauge
        liquidityGauge = ILiquidityGauge(
            address(
                new TransparentUpgradeableProxy(
                    liquidityGaugeImpl,
                    DAO.PROXY_ADMIN,
                    abi.encodeWithSignature(
                        "initialize(address,address,address,address,address,address)",
                        address(sdPendle),
                        address(this),
                        DAO.SDT,
                        DAO.VESDT,
                        DAO.VESDT_BOOST_PROXY,
                        DAO.LOCKER_SDT_DISTRIBUTOR
                    )
                )
            )
        );

        // Deploy and Intialize the PendleLocker contract
        pendleLocker = new PendleLocker(address(this), address(this));

        // Deploy Depositor Contract
        depositor = new PendleDepositor(address(_PENDLE), address(pendleLocker), address(sdPendle));
        depositor.setGauge(address(liquidityGauge));
        sdPendle.setOperator(address(depositor));
        pendleLocker.setPendleDepositor(address(depositor));

        // Deploy Accumulator Contract
        pendleAccumulator = new PendleAccumulator(address(liquidityGauge), daoRecipient, bribeRecipient, veSdtFeeProxy);

        // Deploy veSdtFeePendleProxy
        veSdtFeePendleProxy = new VeSDTFeePendleProxy();

        // Setters
        pendleAccumulator.setLocker(address(pendleLocker));
        pendleLocker.setAccumulator(address(pendleAccumulator));

        // Add Reward to LGV4
        liquidityGauge.add_reward(WETH, address(pendleAccumulator));

        // Mint PENDLE to the locker
        deal(address(_PENDLE), address(pendleLocker), amount);

        uint128 lockTime = uint128(((block.timestamp + 104 * 1 weeks) / 1 weeks) * 1 weeks);
        pendleLocker.createLock(amount, lockTime);

        // Mint PENDLE to the adresss(this)
        deal(address(_PENDLE), address(this), amount);
        // Add Weth to the fee proxy
        deal(WETH, address(veSdtFeePendleProxy), 1e18);
    }

    function testInitialStateDepositor() public {
        (, uint256 end) = vePENDLE.positionData(address(pendleLocker));
        assertEq(end, depositor.unlockTime());
    }

    function testDepositThroughtDepositor() public {
        // Deposit PENDLE to the pendleLocker through the Depositor
        _PENDLE.approve(address(depositor), amount);
        depositor.deposit(amount, true, false, address(this));

        assertEq(sdPendle.balanceOf(address(this)), amount);
        assertEq(liquidityGauge.balanceOf(address(this)), 0);
    }

    function testDepositThroughtDepositorWithStake() public {
        // Deposit PENDLE to the pendleLocker through the Depositor
        _PENDLE.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(liquidityGauge.balanceOf(address(this)), amount);
    }

    function testDepositorIncreaseTime() public {
        // Deposit PENDLE to the pendleLocker through the Depositor
        _PENDLE.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        assertEq(liquidityGauge.balanceOf(address(this)), amount);
        (, uint128 oldEnd) = vePENDLE.positionData(address(pendleLocker));
        // Increase Time
        vm.warp(block.timestamp + 2 * WEEK);
        uint256 newExpectedEnd = (block.timestamp + 104 * WEEK) / WEEK * WEEK;

        deal(address(_PENDLE), address(this), amount);
        _PENDLE.approve(address(depositor), amount);
        depositor.deposit(amount, true, true, address(this));

        (, uint128 end) = vePENDLE.positionData(address(pendleLocker));

        assertGt(end, oldEnd);
        assertEq(end, newExpectedEnd);
        assertEq(liquidityGauge.balanceOf(address(this)), 2 * amount);
    }

    function testVeSDTFeePendleProxy() public {
        uint256 claimerFraxBalanceBefore = IERC20(FRAX).balanceOf(address(this));
        uint256 feeDBalanceBefore = IERC20(SD_FRAX_3CRV).balanceOf(DAO.FEE_DISTRIBUTOR);
        // calculate claimer amount
        uint256 claimerAmount = veSdtFeePendleProxy.claimableByKeeper();
        // calculate min amount out directly on WETH/FRAX LP contract
        uint256 amountOutMin =
            IFraxLP(WETH_FRAX_LP).getAmountOut(IERC20(WETH).balanceOf(address(veSdtFeePendleProxy)), WETH);
        veSdtFeePendleProxy.sendRewards(amountOutMin);
        uint256 claimerFraxBalanceAfter = IERC20(FRAX).balanceOf(address(this));
        uint256 feeDBalanceAfter = IERC20(SD_FRAX_3CRV).balanceOf(DAO.FEE_DISTRIBUTOR);
        assertEq(claimerFraxBalanceAfter - claimerFraxBalanceBefore, claimerAmount);
        assertGt(feeDBalanceAfter, feeDBalanceBefore);

        uint256 proxyWethBalance = IERC20(WETH).balanceOf(address(veSdtFeePendleProxy));
        uint256 proxyFraxBalance = IERC20(FRAX).balanceOf(address(veSdtFeePendleProxy));
        uint256 proxySdFrax3CrvBalance = IERC20(SD_FRAX_3CRV).balanceOf(address(veSdtFeePendleProxy));
        assertEq(proxyWethBalance, 0);
        assertEq(proxyFraxBalance, 0);
        assertEq(proxySdFrax3CrvBalance, 0);
    }
}
