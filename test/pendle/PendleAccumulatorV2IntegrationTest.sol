// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

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
    VyperDeployer vyperDeployer = new VyperDeployer();

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

    // Helper
    uint128 internal constant amount = 100e18;

    uint256 public DAY = AddressBook.DAY;
    uint256 public WEEK = AddressBook.WEEK;
    uint256 public YEAR = AddressBook.YEAR;

    IERC20 public WETH = IERC20(AddressBook.WETH);

    /// List of pools Pendle Locker voted for and eligible to rewards previous to the block 17621271.
    address public constant POOL_1 = 0x2EC8C498ec997aD963969a2c93Bf7150a1F5b213;
    address public constant POOL_2 = 0x4f30A9D41B80ecC5B94306AB4364951AE3170210;
    address public constant POOL_3 = 0xd1434df1E2Ad0Cb7B3701a751D01981c7Cf2Dd62;
    address public constant POOL_4 = 0x08a152834de126d2ef83D612ff36e4523FD0017F;
    address public constant POOL_5 = 0x7D49E5Adc0EAAD9C027857767638613253eF125f;

    function setUp() public virtual {
        vm.rollFork(17621271);

        // Deploy Accumulator Contract
        pendleAccumulator = new PendleAccumulatorV2( 
            address(this),
            daoRecipient,
            bountyRecipient,
            address(veSdtFeePendleProxy)
            );

        vm.prank(pendleLocker.governance());
        pendleLocker.setAccumulator(address(pendleAccumulator));

        // Add Reward to LGV4
        vm.startPrank(liquidityGauge.admin());
        liquidityGauge.add_reward(address(WETH), address(pendleAccumulator));
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
        assertEq(WETH.balanceOf(address(liquidityGauge)), 0);

        pendleAccumulator.claimForVePendle();

        uint256 daoPart = WETH.balanceOf(daoRecipient);
        uint256 bountyPart = WETH.balanceOf(bountyRecipient);
        uint256 veSdtFeePart = WETH.balanceOf(veSdtFeeProxy);
        uint256 gaugePart = WETH.balanceOf(address(liquidityGauge));
        uint256 claimerPart = WETH.balanceOf(address(this));

        /// WETH is distributed over 4 weeks to Accumulator.
        uint256 remaining = WETH.balanceOf(address(pendleAccumulator));

        uint256 total = claimerPart + daoPart + bountyPart + gaugePart + veSdtFeePart + remaining;

        assertEq(total * pendleAccumulator.claimerFee() / 10_000, claimerPart);
        assertEq(total * pendleAccumulator.daoFee() / 10_000, daoPart);
        assertEq(total * pendleAccumulator.bountyFee() / 10_000, bountyPart);
        assertEq(total * pendleAccumulator.veSdtFeeProxyFee() / 10_000, veSdtFeePart);

        assertEq(WETH.balanceOf(address(liquidityGauge)), remaining / 3); // One week has already been distributed to the gauge so we have 3 weeks left.
    }

    function testDistributeAllRewardsOff() public {
        assertFalse(pendleAccumulator.distributeVotersRewards());

        address[] memory pools = new address[](6);
        pools[0] = address(vePENDLE);
        pools[0] = POOL_1;
        pools[1] = POOL_2;
        pools[2] = POOL_3;
        pools[3] = POOL_4;
        pools[5] = POOL_5;

        vm.expectRevert(PendleAccumulatorV2.WRONG_CLAIM.selector);
        pendleAccumulator.claimForVoters(pools);
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

        address[] memory pools = new address[](6);
        pools[0] = address(vePENDLE);
        pools[1] = POOL_1;
        pools[2] = POOL_2;
        pools[3] = POOL_3;
        pools[4] = POOL_4;
        pools[5] = POOL_5;

        pendleAccumulator.setDistributeVotersRewards(true);

        //Check Dao recipient
        assertEq(WETH.balanceOf(daoRecipient), 0);
        //// Check Bounty recipient
        assertEq(WETH.balanceOf(bountyRecipient), 0);
        //// Check VeSdtFeeProxy
        assertEq(WETH.balanceOf(address(veSdtFeeProxy)), 0);
        //// Check lgv4
        assertEq(WETH.balanceOf(address(liquidityGauge)), 0);

        pendleAccumulator.claimForAll(pools);

        uint256 daoPart = WETH.balanceOf(daoRecipient);
        uint256 bountyPart = WETH.balanceOf(bountyRecipient);
        uint256 veSdtFeePart = WETH.balanceOf(veSdtFeeProxy);
        uint256 gaugePart = WETH.balanceOf(address(liquidityGauge));
        uint256 claimerPart = WETH.balanceOf(address(this));

        /// WETH is distributed over 4 weeks so Accumulator.
        uint256 remaining = WETH.balanceOf(address(pendleAccumulator));

        uint256 total = claimerPart + daoPart + bountyPart + gaugePart + veSdtFeePart + remaining;

        assertEq(total * pendleAccumulator.claimerFee() / 10_000, claimerPart);
        assertEq(total * pendleAccumulator.daoFee() / 10_000, daoPart);
        assertEq(total * pendleAccumulator.bountyFee() / 10_000, bountyPart);
        assertEq(total * pendleAccumulator.veSdtFeeProxyFee() / 10_000, veSdtFeePart);

        assertEq(WETH.balanceOf(address(liquidityGauge)), remaining / 3); // One week has already been distributed to the gauge so we have 3 weeks left.
    }

    function testAccumulatorRewardsWithClaimerFees() public {
        pendleAccumulator.setClaimerFee(1000); // 10%

        uint256 claimerBalanceBefore = WETH.balanceOf(address(this));

        pendleAccumulator.claimForVePendle();

        uint256 claimerBalanceEarned = WETH.balanceOf(address(this)) - claimerBalanceBefore;

        assertEq(
            (claimerBalanceEarned + WETH.balanceOf(address(liquidityGauge))) * pendleAccumulator.claimerFee() / 10_000,
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
        address[] memory pools = new address[](6);
        pools[0] = address(vePENDLE);
        pools[1] = POOL_1;
        pools[2] = POOL_2;
        pools[3] = POOL_3;
        pools[4] = POOL_4;
        pools[5] = POOL_5;

        pendleAccumulator.claimForAll(pools);
        uint256 periodsToNotify = pendleAccumulator.periodsToNotify();
        assertEq(periodsToNotify, 3);
        vm.expectRevert(PendleAccumulatorV2.NO_BALANCE.selector);
        pendleAccumulator.claimForAll(pools);

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
}
