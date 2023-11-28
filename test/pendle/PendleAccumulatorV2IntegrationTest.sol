// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {PendleLocker} from "src/pendle/locker/PendleLocker.sol";
import {IVePendle} from "src/base/interfaces/IVePendle.sol";
import {PendleDepositor} from "src/pendle/depositor/PendleDepositor.sol";

import {IPendleFeeDistributor} from "src/base/interfaces/IPendleFeeDistributor.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IFraxSwapRouter} from "src/base/interfaces/IFraxSwapRouter.sol";

import {PendleAccumulatorV2} from "src/pendle/accumulator/PendleAccumulatorV2.sol";
import {VeSDTFeePendleProxy} from "src/pendle/ve-sdt-fee-proxy/VeSDTFeePendleProxy.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IFraxLP {
    function getAmountOut(uint256 amount, address tokenIn) external view returns (uint256);
}

contract PendleAccumulatorV2IntegrationTest is Test {
    address public constant SD_FRAX_3CRV = 0x5af15DA84A4a6EDf2d9FA6720De921E1026E37b7;

    // External Contracts
    PendleLocker internal pendleLocker = PendleLocker(AddressBook.PENDLE_LOCKER);

    // Liquid Lockers Contracts
    IERC20 internal PENDLE = IERC20(AddressBook.PENDLE);
    IVePendle internal vePENDLE = IVePendle(AddressBook.VE_PENDLE);
    sdToken internal sdPendle = sdToken(AddressBook.SD_PENDLE);

    PendleDepositor internal depositor = PendleDepositor(AddressBook.PENDLE_DEPOSITOR);
    ILiquidityGauge internal liquidityGauge = ILiquidityGauge(AddressBook.GAUGE_SDPENDLE);
    PendleAccumulatorV2 internal pendleAccumulator;
    VeSDTFeePendleProxy internal veSdtFeePendleProxy = VeSDTFeePendleProxy(AddressBook.VE_SDT_PENDLE_FEE_PROXY);

    address public daoRecipient = makeAddr("dao");
    address public bountyRecipient = makeAddr("bounty");
    address public veSdtFeeProxy = makeAddr("feeProxy");
    address public bot = makeAddr("bot");
    address public votersRewardRecipient = makeAddr("vrr");

    // Helper
    uint128 internal constant amount = 100e18;

    uint256 public DAY = AddressBook.DAY;
    uint256 public WEEK = AddressBook.WEEK;
    uint256 public YEAR = AddressBook.YEAR;

    address public constant PENDLE_FEE_D = 0x8C237520a8E14D658170A633D96F8e80764433b9;

    IERC20 public WETH = IERC20(AddressBook.WETH);

    /// List of pools Pendle Locker voted for and eligible to rewards previous to the block 17621271.
    address public constant POOL_1 = 0xd1434df1E2Ad0Cb7B3701a751D01981c7Cf2Dd62;
    address public constant POOL_2 = 0xfb8f489df4e04609F4f4e54F586f960818B70041;
    address public constant POOL_3 = 0x14FbC760eFaF36781cB0eb3Cb255aD976117B9Bd;
    address public constant POOL_4 = 0xa0192f6567f8f5DC38C53323235FD08b318D2dcA;
    address public constant POOL_5 = 0xC8fD1F1E059d97ec71AE566DD6ca788DC92f36AF;
    address public constant POOL_6 = 0xFd8AeE8FCC10aac1897F8D5271d112810C79e022;
    address public constant POOL_7 = 0x08a152834de126d2ef83D612ff36e4523FD0017F;
    address public constant POOL_8 = 0xEDa1D0e1681D59dea451702963d6287b844Cb94C;
    address public constant POOL_9 = 0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2;
    address public constant POOL_10 = 0x0A21291A184cf36aD3B0a0def4A17C12Cbd66A14;
    address public constant POOL_11 = 0x7D49E5Adc0EAAD9C027857767638613253eF125f;
    address public constant POOL_12 = 0x2EC8C498ec997aD963969a2c93Bf7150a1F5b213;
    address public constant POOL_13 = 0x080f52A881ba96EEE2268682733C857c560e5dd4;

    address[] public allPools = [
        0x4f30A9D41B80ecC5B94306AB4364951AE3170210, // VE_PENDLE
        0xd1434df1E2Ad0Cb7B3701a751D01981c7Cf2Dd62,
        0xfb8f489df4e04609F4f4e54F586f960818B70041,
        0x14FbC760eFaF36781cB0eb3Cb255aD976117B9Bd,
        0xa0192f6567f8f5DC38C53323235FD08b318D2dcA,
        0xC8fD1F1E059d97ec71AE566DD6ca788DC92f36AF,
        0xFd8AeE8FCC10aac1897F8D5271d112810C79e022,
        0x08a152834de126d2ef83D612ff36e4523FD0017F,
        0xEDa1D0e1681D59dea451702963d6287b844Cb94C,
        0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2,
        0x0A21291A184cf36aD3B0a0def4A17C12Cbd66A14,
        0x7D49E5Adc0EAAD9C027857767638613253eF125f,
        0x2EC8C498ec997aD963969a2c93Bf7150a1F5b213,
        0x080f52A881ba96EEE2268682733C857c560e5dd4
    ];

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 18045826);
        vm.selectFork(forkId);
        // Deploy Accumulator Contract
        pendleAccumulator = new PendleAccumulatorV2(
            address(this), daoRecipient, bountyRecipient, address(veSdtFeePendleProxy), votersRewardRecipient
        );

        vm.prank(pendleLocker.governance());
        pendleLocker.setAccumulator(address(pendleAccumulator));

        // Add Reward to LGV4
        vm.startPrank(liquidityGauge.admin());
        liquidityGauge.set_reward_distributor(address(WETH), address(pendleAccumulator));
        liquidityGauge.add_reward(address(PENDLE), address(pendleAccumulator));
        vm.stopPrank();
    }

    function testAccumulatorRewards() public {
        //Check Dao recipient
        assertEq(WETH.balanceOf(daoRecipient), 0);
        //// Check Bounty recipient
        assertEq(WETH.balanceOf(bountyRecipient), 0);
        //// Check VeSdtFeeProxy
        assertEq(WETH.balanceOf(address(veSdtFeeProxy)), 0);
        //// Check lgv4
        uint256 gaugeBalanceBefore = WETH.balanceOf(address(liquidityGauge));

        pendleAccumulator.claimForVePendle();
        pendleAccumulator.notifyReward(address(WETH));

        uint256 daoPart = WETH.balanceOf(daoRecipient);
        uint256 bountyPart = WETH.balanceOf(bountyRecipient);
        uint256 veSdtFeePart = WETH.balanceOf(veSdtFeeProxy);
        uint256 gaugePart = WETH.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore;
        uint256 claimerPart = WETH.balanceOf(address(this));

        /// WETH is distributed over 4 weeks to Accumulator.
        uint256 remaining = WETH.balanceOf(address(pendleAccumulator));

        uint256 total = claimerPart + daoPart + bountyPart + gaugePart + veSdtFeePart + remaining;

        assertEq(total * pendleAccumulator.claimerFee() / 10_000, claimerPart);
        assertEq(total * pendleAccumulator.daoFee() / 10_000, daoPart);
        assertEq(total * pendleAccumulator.bountyFee() / 10_000, bountyPart);
        assertEq(total * pendleAccumulator.veSdtFeeProxyFee() / 10_000, veSdtFeePart);

        //assertEq(gaugePart, remaining / 3); // One week has already been distributed to the gauge so we have 3 weeks left.
    }

    function testDistributeAllRewardsOff() public {
        assertFalse(pendleAccumulator.distributeVotersRewards());

        vm.expectRevert(PendleAccumulatorV2.WRONG_CLAIM.selector);
        pendleAccumulator.claimForVoters(allPools);
    }

    function testDistributeAllRewardsOnOnlyGovernance() public {
        assertFalse(pendleAccumulator.distributeVotersRewards());

        vm.expectRevert(PendleAccumulatorV2.NOT_ALLOWED.selector);
        vm.prank(address(0xBEEF));
        pendleAccumulator.setDistributeVotersRewards(true);

        assertFalse(pendleAccumulator.distributeVotersRewards());
    }

    function testDistributeRewardsForVoter() public {
        assertFalse(pendleAccumulator.distributeVotersRewards());

        pendleAccumulator.setDistributeVotersRewards(true);

        //Check Dao recipient
        assertEq(WETH.balanceOf(daoRecipient), 0);
        //// Check Bounty recipient
        assertEq(WETH.balanceOf(bountyRecipient), 0);
        //// Check VeSdtFeeProxy
        assertEq(WETH.balanceOf(address(veSdtFeeProxy)), 0);
        //// Check lgv4
        uint256 gaugeBalanceBefore = WETH.balanceOf(address(liquidityGauge));

        pendleAccumulator.claimForAll(allPools);

        uint256 daoPart = WETH.balanceOf(daoRecipient);
        uint256 bountyPart = WETH.balanceOf(bountyRecipient);
        uint256 veSdtFeePart = WETH.balanceOf(veSdtFeeProxy);
        uint256 gaugePart = WETH.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore;
        uint256 claimerPart = WETH.balanceOf(address(this));

        /// WETH is distributed over 4 weeks so Accumulator.
        uint256 remaining = WETH.balanceOf(address(pendleAccumulator));

        uint256 total = claimerPart + daoPart + bountyPart + gaugePart + veSdtFeePart + remaining;

        assertEq(total * pendleAccumulator.claimerFee() / 10_000, claimerPart);
        assertEq(total * pendleAccumulator.daoFee() / 10_000, daoPart);
        assertEq(total * pendleAccumulator.bountyFee() / 10_000, bountyPart);
        assertEq(total * pendleAccumulator.veSdtFeeProxyFee() / 10_000, veSdtFeePart);

        //assertEq(gaugePart, remaining / 3); // One week has already been distributed to the gauge so we have 3 weeks left.
    }

    function testAccumulatorRewardsWithClaimerFees() public {
        pendleAccumulator.setClaimerFee(1000); // 10%

        uint256 claimerBalanceBefore = WETH.balanceOf(address(this));
        uint256 gaugeBalanceBefore = WETH.balanceOf(address(liquidityGauge));

        pendleAccumulator.claimForVePendle();

        uint256 claimerBalanceEarned = WETH.balanceOf(address(this)) - claimerBalanceBefore;

        assertEq(
            (claimerBalanceEarned + WETH.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore)
                * pendleAccumulator.claimerFee() / 10_000,
            claimerBalanceEarned
        );
    }

    function testPushTokens() public {
        uint256 amountToPush = 10e18;
        deal(address(WETH), address(pendleAccumulator), amountToPush);
        pendleAccumulator.togglePullAllowance(bot);

        address[] memory tokens = new address[](1);
        tokens[0] = address(WETH);
        uint256[] memory amountsToPush = new uint256[](1);
        amountsToPush[0] = amountToPush;
        uint256 balanceBeforePull = WETH.balanceOf(bot);
        vm.prank(bot);
        pendleAccumulator.pullTokens(tokens, amountsToPush);
        uint256 balanceAfterPull = WETH.balanceOf(bot);
        assertEq(balanceAfterPull - balanceBeforePull, amountToPush);
        pendleAccumulator.togglePullAllowance(bot);
        vm.prank(bot);
        vm.expectRevert(PendleAccumulatorV2.NOT_ALLOWED_TO_PULL.selector);
        pendleAccumulator.pullTokens(tokens, amountsToPush);
    }

    function testPeriodsToNotify() public {
        pendleAccumulator.claimForAll(allPools);
        uint256 periodsToNotify = pendleAccumulator.periodsToNotify();
        assertEq(periodsToNotify, 3);
        vm.expectRevert(PendleAccumulatorV2.NO_BALANCE.selector);
        pendleAccumulator.claimForAll(allPools);

        // fork block number is on tuesday
        // skipping 2 days to trigger the new notify
        skip(2 days);

        pendleAccumulator.notifyReward(address(WETH));
        periodsToNotify = pendleAccumulator.periodsToNotify();
        assertEq(periodsToNotify, 2);

        skip(7 days);

        pendleAccumulator.notifyReward(address(WETH));
        periodsToNotify = pendleAccumulator.periodsToNotify();
        assertEq(periodsToNotify, 1);

        skip(7 days);

        pendleAccumulator.notifyReward(address(WETH));
        periodsToNotify = pendleAccumulator.periodsToNotify();
        assertEq(periodsToNotify, 0);

        uint256 accBalance = WETH.balanceOf(address(pendleAccumulator));
        assertEq(accBalance, 0);
    }

    function testClaimForVePendle() public {
        pendleAccumulator.claimForVePendle();
        vm.expectRevert(PendleAccumulatorV2.NO_REWARD.selector);
        pendleAccumulator.claimForVePendle();
    }
}
