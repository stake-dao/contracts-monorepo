// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {CurveAccumulatorV2} from "src/curve/accumulator/CurveAccumulatorV2.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {IStrategy} from "herdaddy/interfaces/IStrategy.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {FeeReceiverMock} from "test/utils/mocks/FeeReceiverMock.sol";

interface IStrategyGov is IStrategy {
    function setAccumulator(address _accumulator) external;
    function setFeeReceiver(address _feeReceiver) external;
    function governance() external view returns (address);
}

contract CurveAccumulatorV2IntegrationTest is Test {
    CurveAccumulatorV2 public accumulator;
    IStrategyGov public strategy = IStrategyGov(0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd);
    address public crv;
    address public crv3;
    ILiquidityGauge public sdCRVLG;
    ILocker public crvLocker;
    FeeReceiverMock public feeReceiver;

    //address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CRV3 = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public constant GOV = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address public sdtDistributor = 0x8Dc551B4f5203b51b5366578F42060666D42AB5E;

    address daoFeeRecipient = vm.addr(1);
    address liquidityFeeRecipient = vm.addr(2);

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 19585407); // One block before an harvest (with 3RV Rewards)
        //uint256 forkId = vm.createFork(vm.rpcUrl("tdly")); // One block before an harvest (with 3RV Rewards)
        vm.selectFork(forkId);

        // Deploy a mock fee receiver
        feeReceiver = new FeeReceiverMock(address(this));

        skip(7 days);

        crv = CRV.TOKEN;
        crv3 = CRV3;
        sdCRVLG = ILiquidityGauge(CRV.GAUGE);
        crvLocker = ILocker(CRV.LOCKER);
        accumulator = new CurveAccumulatorV2(
            address(sdCRVLG), address(crvLocker), daoFeeRecipient, liquidityFeeRecipient, address(this)
        );

        address[] memory receivers = new address[](1);
        uint256[] memory fees = new uint256[](1);

        receivers[0] = address(accumulator);
        fees[0] = 10000; // 100% to accumulator

        // Set reward token for accumulator in fee receiver
        feeReceiver.setRepartition(CRV.TOKEN, receivers, fees);

        // Set fee receiver in accumulator
        accumulator.setFeeReceiver(address(feeReceiver));

        // Set SDT distributor in accumulator
        accumulator.setDistributor(sdtDistributor);

        vm.startPrank(GOV);
        sdCRVLG.set_reward_distributor(CRV.TOKEN, address(accumulator));
        sdCRVLG.set_reward_distributor(CRV3, address(accumulator));
        strategy.setAccumulator(address(accumulator));
        strategy.setFeeReceiver(address(feeReceiver)); // Set fee receiver in strategy
        vm.stopPrank();
    }

    function testAccumulator3CRVRewards() public {
        //Check Dao recipient
        assertEq(ERC20(CRV3).balanceOf(daoFeeRecipient), 0);
        //// Liquidity Fee Recipient
        assertEq(ERC20(CRV3).balanceOf(liquidityFeeRecipient), 0);
        //// Check lgv4
        uint256 gaugeBalanceBefore = ERC20(CRV3).balanceOf(address(sdCRVLG));

        uint256 daoPart = ERC20(CRV3).balanceOf(daoFeeRecipient);
        uint256 liquidityPart = ERC20(CRV3).balanceOf(liquidityFeeRecipient);
        uint256 claimerPart = ERC20(CRV3).balanceOf(address(this));
        uint256 gaugePart = ERC20(CRV3).balanceOf(address(sdCRVLG)) - gaugeBalanceBefore;

        assertEq(daoPart, 0);
        assertEq(liquidityPart, 0);
        assertEq(claimerPart, 0);
        assertEq(gaugePart, 0);

        // First, simulate a claim with a random contract, to see the total. then revert. we have the total amount of CRV3
        uint256 snapshot = vm.snapshot();
        vm.prank(GOV);
        strategy.setAccumulator(address(0xBAD));
        vm.prank(address(0xBAD));
        strategy.claimNativeRewards();
        uint256 realTotal = ERC20(CRV3).balanceOf(address(0xBAD));
        vm.revertTo(snapshot);

        accumulator.claimAndNotifyAll(false, false, false); // Do not notify SDT, do not pull from reward splitter, do not distribute rewards from strategy

        _checkFeesOnClaim(CRV3, gaugeBalanceBefore, realTotal);
    }

    function testAccumulatorAllRewards() public {
        // 3CRV + CRV (sent from strategy via reward splitter)

        // 3CRV
        //Check Dao recipient for 3CRV
        uint256 daoPart3CRV = ERC20(CRV3).balanceOf(daoFeeRecipient);
        assertEq(daoPart3CRV, 0);
        // Liquidity Fee Recipient for 3CRV
        uint256 liquidityPart3CRV = ERC20(CRV3).balanceOf(liquidityFeeRecipient);
        assertEq(liquidityPart3CRV, 0);
        // Check lgv4 for 3CRV
        uint256 gaugeBalanceBefore3CRV = ERC20(CRV3).balanceOf(address(sdCRVLG));
        uint256 gaugePart3CRV = ERC20(CRV3).balanceOf(address(sdCRVLG)) - gaugeBalanceBefore3CRV;
        assertEq(gaugePart3CRV, 0);

        // CRV
        //Check Dao recipient for CRV
        uint256 daoPartCRV = ERC20(CRV.TOKEN).balanceOf(daoFeeRecipient);
        assertEq(daoPartCRV, 0);
        // Liquidity Fee Recipient for CRV
        uint256 liquidityPartCRV = ERC20(CRV.TOKEN).balanceOf(liquidityFeeRecipient);
        assertEq(liquidityPartCRV, 0);
        // Check lgv4 for CRV
        uint256 gaugeBalanceBeforeCRV = ERC20(CRV.TOKEN).balanceOf(address(sdCRVLG));
        uint256 gaugePartCRV = ERC20(CRV.TOKEN).balanceOf(address(sdCRVLG)) - gaugeBalanceBeforeCRV;
        assertEq(gaugePartCRV, 0);

        // First, simulate a claim with a random contract, to see the total. then revert. we have the total amount of CRV3
        uint256 snapshot3CRV = vm.snapshot();
        vm.prank(GOV);
        strategy.setAccumulator(address(0xBAD));
        vm.prank(address(0xBAD));
        strategy.claimNativeRewards();
        uint256 realTotal3CRV = ERC20(CRV3).balanceOf(address(0xBAD));
        vm.revertTo(snapshot3CRV);

        // Same to check CRV Rewards
        uint256 snapshotCRV = vm.snapshot();
        vm.prank(GOV);
        strategy.setFeeReceiver(address(0xBAD));
        strategy.claimProtocolFees();
        uint256 realTotalCRV = ERC20(CRV.TOKEN).balanceOf(address(0xBAD));
        vm.revertTo(snapshotCRV);

        accumulator.claimAndNotifyAll(false, true, true); // Do not notify SDT, pull from reward splitter, distribute rewards from strategy

        _checkFeesOnClaim(CRV3, gaugeBalanceBefore3CRV, realTotal3CRV);
        //_checkFeesOnClaim(CRV.TOKEN, gaugeBalanceBeforeCRV, realTotalCRV); ==> Fee splitter supposed to already distribute CRV rewards accordingly
        // do not re-charge fees here, all to gauge
        assertEq(ERC20(CRV.TOKEN).balanceOf(address(sdCRVLG)), realTotalCRV + gaugeBalanceBeforeCRV);
    }

    function testNotifyReward() external {
        uint256 amountToTopUp = 1e18;
        uint256 gaugeBalanceBefore = ERC20(CRV3).balanceOf(address(sdCRVLG));
        deal(CRV3, address(accumulator), amountToTopUp);
        accumulator.notifyReward(CRV3, false, false);
        assertEq(ERC20(CRV3).balanceOf(address(accumulator)), 0);
        _checkFeesOnClaim(CRV3, gaugeBalanceBefore, amountToTopUp);
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

    function _checkFeesOnClaim(address _token, uint256 _gaugeBalanceBefore, uint256 _realTotal) internal {
        uint256 gaugeBalance = ERC20(_token).balanceOf(address(sdCRVLG)) - _gaugeBalanceBefore;
        uint256 daoPart = ERC20(_token).balanceOf(daoFeeRecipient);
        uint256 liquidityPart = ERC20(_token).balanceOf(liquidityFeeRecipient);
        uint256 claimerPart = ERC20(_token).balanceOf(address(this));
        uint256 totalClaimed = gaugeBalance + daoPart + liquidityPart + claimerPart;
        assertEq(totalClaimed, _realTotal);
        assertEq(daoPart, totalClaimed * accumulator.daoFee() / 10_000);
        assertEq(liquidityPart, totalClaimed * accumulator.liquidityFee() / 10_000);
        assertEq(claimerPart, totalClaimed * accumulator.claimerFee() / 10_000);
    }
}
