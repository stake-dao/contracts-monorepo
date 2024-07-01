// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {IYearnStrategy} from "src/base/interfaces/IYearnStrategy.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IFeeReceiver} from "herdaddy/interfaces/IFeeReceiver.sol";
import {YFIAccumulatorV2} from "src/yearn/accumulator/YFIAccumulatorV2.sol";

contract YearnAccumulatorV2Test is Test {
    YFIAccumulatorV2 public accumulator;
    IYearnStrategy public strategy = IYearnStrategy(0x1be150a35bb8233d092747eBFDc75FB357c35168);
    address public yfi;
    ILiquidityGauge public sdYfiLG;
    ILocker public yfiLocker;
    address public constant DYFI = 0x41252E8691e964f7DE35156B68493bAb6797a275;
    address public constant GOV = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address public constant FEE_RECEIVER = 0x60136fefE23D269aF41aB72DE483D186dC4318D6;

    address public constant DYFI_REWARD_POOL = 0x2391Fc8f5E417526338F5aa3968b1851C16D894E;
    address public constant YFI_REWARD_POOL = 0xb287a1964AEE422911c7b8409f5E5A273c1412fA;

    address daoFeeRecipient = vm.addr(1);
    address liquidityFeeRecipient = vm.addr(2);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 19_968_542);
        vm.selectFork(forkId);
        yfi = YFI.TOKEN;
        sdYfiLG = ILiquidityGauge(YFI.GAUGE);
        yfiLocker = ILocker(YFI.LOCKER);
        accumulator = new YFIAccumulatorV2(address(sdYfiLG), address(yfiLocker), address(this));

        address[] memory feeSplitReceivers = new address[](2);
        uint256[] memory feeSplitFees = new uint256[](2);

        feeSplitReceivers[0] = daoFeeRecipient;
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = liquidityFeeRecipient;
        feeSplitFees[1] = 1000; // 5% to liquidity

        vm.startPrank(GOV);
        sdYfiLG.set_reward_distributor(yfi, address(accumulator));
        sdYfiLG.set_reward_distributor(DYFI, address(accumulator));

        strategy.setAccumulator(address(accumulator));
        vm.stopPrank();
        vm.prank(address(strategy));
        // disable the acc actions at locker side
        yfiLocker.setAccumulator(address(0));

        /// Set the Fee Receiver in the accumulator.
        accumulator.setFeeReceiver(FEE_RECEIVER);

        /// Setup the accumulator in the Fee Receiver.
        //vm.prank(GOV);
        //IFeeReceiver(FEE_RECEIVER).setAccumulator(DYFI, address(accumulator));

        address[] memory receivers = new address[](2);
        uint256[] memory fees = new uint256[](2);

        receivers[0] = address(accumulator);
        receivers[1] = GOV;

        fees[0] = 5000;
        fees[1] = 5000;

        //vm.prank(GOV);
        //IFeeReceiver(FEE_RECEIVER).setRepartition(DYFI, receivers, fees);

        deal(DYFI, DYFI_REWARD_POOL, 100e18);
        deal(yfi, YFI_REWARD_POOL, 100e18);

        /// Skip 1 week for distribution.
        skip(1 weeks);
    }

    function testDyfiClaim() external {
        uint256 snapshotBalance = ERC20(DYFI).balanceOf(address(sdYfiLG));
        // notify DYFI to the sdDyfi gauge
        accumulator.claimTokenAndNotifyAll(DYFI, false, false, false);
        assertEq(ERC20(DYFI).balanceOf(address(accumulator)), 0);
        _checkFeesOnClaim(DYFI, snapshotBalance);
    }

    function testYfiClaim() external {
        uint256 snapshotBalance = ERC20(yfi).balanceOf(address(sdYfiLG));

        // notify YFI to the sdDyfi gauge
        accumulator.claimTokenAndNotifyAll(yfi, false, false, false);
        assertEq(ERC20(yfi).balanceOf(address(accumulator)), 0);
        _checkFeesOnClaim(yfi, snapshotBalance);
    }

    function testClaimAll() external {
        uint256 yfi_snapshotBalance = ERC20(yfi).balanceOf(address(sdYfiLG));
        uint256 dyfi_snapshotBalance = ERC20(DYFI).balanceOf(address(sdYfiLG));

        accumulator.claimAndNotifyAll(false, true, true);

        /// Claim from the strategy, and pull from the fee receiver.
        assertEq(ERC20(yfi).balanceOf(address(accumulator)), 0);
        assertEq(ERC20(DYFI).balanceOf(address(accumulator)), 0);

        assertEq(ERC20(DYFI).balanceOf(address(FEE_RECEIVER)), 0);
        assertGt(ERC20(yfi).balanceOf(address(sdYfiLG)), yfi_snapshotBalance);
        assertGt(ERC20(DYFI).balanceOf(address(sdYfiLG)), dyfi_snapshotBalance);
    }

    function testNotifyReward() external {
        uint256 snapshotBalance = ERC20(DYFI).balanceOf(address(sdYfiLG));

        uint256 amountToTopUp = 1e18;
        deal(DYFI, address(accumulator), amountToTopUp);
        accumulator.notifyReward(DYFI, false, false);
        assertEq(ERC20(DYFI).balanceOf(address(accumulator)), 0);
        _checkFeesOnClaim(DYFI, snapshotBalance);
    }

    function testTransferGovernance() external {
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), address(0));
        accumulator.transferGovernance(GOV);
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), GOV);
        vm.prank(GOV);
        accumulator.acceptGovernance();
        assertEq(accumulator.governance(), GOV);
    }

    function _checkFeesOnClaim(address _token, uint256 snapshotBalance) internal {
        uint256 gaugeBalance = ERC20(_token).balanceOf(address(sdYfiLG));

        if (gaugeBalance > snapshotBalance) {
            gaugeBalance -= snapshotBalance;
        } else {
            gaugeBalance = snapshotBalance - gaugeBalance;
        }

        uint256 daoPart = ERC20(_token).balanceOf(daoFeeRecipient);
        uint256 liquidityPart = ERC20(_token).balanceOf(liquidityFeeRecipient);
        uint256 claimerPart = ERC20(_token).balanceOf(address(this));
        uint256 totalClaimed = gaugeBalance + daoPart + liquidityPart + claimerPart;

        YFIAccumulatorV2.Split memory feeSplit = accumulator.getFeeSplit();

        assertEq(daoPart, totalClaimed * feeSplit.fees[0] / 10_000);
        assertEq(liquidityPart, totalClaimed * feeSplit.fees[1] / 10_000);
        assertEq(claimerPart, totalClaimed * accumulator.claimerFee() / 10_000);
    }
}
