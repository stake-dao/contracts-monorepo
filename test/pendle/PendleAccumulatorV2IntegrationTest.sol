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
    address public bribeRecipient = makeAddr("bribe");
    address public veSdtFeeProxy = makeAddr("feeProxy");

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
            bribeRecipient,
            address(veSdtFeePendleProxy)
            );

        // Setters
        pendleAccumulator.setLocker(address(pendleLocker));

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
        //// Check Bribe recipient23
        assertEq(WETH.balanceOf(bribeRecipient), 0);
        //// Check VeSdtFeeProxy
        assertEq(WETH.balanceOf(address(veSdtFeeProxy)), 0);
        //// Check lgv4
        assertEq(WETH.balanceOf(address(liquidityGauge)), 0);

        pendleAccumulator.claimForVePendle();

        uint256 daoPart = WETH.balanceOf(daoRecipient);
        uint256 bribePart = WETH.balanceOf(bribeRecipient);
        uint256 veSdtFeePart = WETH.balanceOf(veSdtFeeProxy);
        uint256 gaugePart = WETH.balanceOf(address(liquidityGauge));

        /// WETH is distributed over 4 weeks to Accumulator.
        uint256 remaining = WETH.balanceOf(address(pendleAccumulator));

        uint256 firstWeekTotal = (remaining / 3 * 4) - remaining;

        assertEq(firstWeekTotal * pendleAccumulator.daoFee() / 10_000, daoPart);
        assertEq(firstWeekTotal * pendleAccumulator.bribeFee() / 10_000, bribePart);
        assertEq(firstWeekTotal * pendleAccumulator.veSdtFeeProxyFee() / 10_000, veSdtFeePart);

        assertEq(WETH.balanceOf(address(liquidityGauge)) + daoPart + bribePart + veSdtFeePart, remaining / 3); // One week has already been distributed to the gauge so we have 3 weeks left.
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
        pendleAccumulator.setDistributeAllRewards(true);

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

        pendleAccumulator.setDistributeAllRewards(true);

        //Check Dao recipient
        assertEq(WETH.balanceOf(daoRecipient), 0);
        //// Check Bribe recipient23
        assertEq(WETH.balanceOf(bribeRecipient), 0);
        //// Check VeSdtFeeProxy
        assertEq(WETH.balanceOf(address(veSdtFeeProxy)), 0);
        //// Check lgv4
        assertEq(WETH.balanceOf(address(liquidityGauge)), 0);

        pendleAccumulator.claimForAll(pools);

        uint256 daoPart = WETH.balanceOf(daoRecipient);
        uint256 bribePart = WETH.balanceOf(bribeRecipient);
        uint256 veSdtFeePart = WETH.balanceOf(veSdtFeeProxy);
        uint256 gaugePart = WETH.balanceOf(address(liquidityGauge));

        /// WETH is distributed over 4 weeks so Accumulator.
        uint256 remaining = WETH.balanceOf(address(pendleAccumulator));
        uint256 firstWeekTotal = (remaining / 3 * 4) - remaining;

        assertEq(firstWeekTotal * pendleAccumulator.daoFee() / 10_000, daoPart);
        assertEq(firstWeekTotal * pendleAccumulator.bribeFee() / 10_000, bribePart);
        assertEq(firstWeekTotal * pendleAccumulator.veSdtFeeProxyFee() / 10_000, veSdtFeePart);

        assertEq(WETH.balanceOf(address(liquidityGauge)) + daoPart + bribePart + veSdtFeePart, remaining / 3); // One week has already been distributed to the gauge so we have 3 weeks left.
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
}
