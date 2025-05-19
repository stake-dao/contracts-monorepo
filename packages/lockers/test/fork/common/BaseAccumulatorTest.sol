// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {ILiquidityGauge} from "src/common/interfaces/ILiquidityGauge.sol";
import {CommonBase} from "test/common/CommonBase.sol";

abstract contract BaseAccumulatorTest is CommonBase, Test {
    uint256 internal blockNumber;
    string internal chain;

    constructor(
        uint256 _blockNumber,
        string memory _chain,
        address _locker,
        address _sdToken,
        address _veToken,
        address _liquidityGauge,
        address _rewardToken,
        address _strategyRewardToken
    ) {
        blockNumber = _blockNumber;
        chain = _chain;
        locker = _locker;

        sdToken = _sdToken;
        veToken = _veToken;
        liquidityGauge = ILiquidityGauge(_liquidityGauge);

        rewardToken = ERC20(_rewardToken);
        strategyRewardToken = ERC20(_strategyRewardToken);

        vm.label(locker, "locker");
        vm.label(sdToken, "sdToken");
        vm.label(veToken, "veToken");
        vm.label(address(liquidityGauge), "liquidityGauge");
        vm.label(address(rewardToken), "rewardToken");
        vm.label(address(strategyRewardToken), "strategyRewardToken");
    }

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl(chain), blockNumber);
        vm.selectFork(forkId);

        // Each time there is an attempt to call the missing `execTransactionFromModuleReturnData` function from the already deployed locker,
        // the VM will keep the context (address(this) == deployed locker) but will execute the bytecode of the function
        // from the `LockerMock` contract implementation. It's like extending the already deployed locker with the function
        // `execTransactionFromModuleReturnData` defined in the `LockerMock` contract.
        address lockerMock = address(new LockerMock());
        vm.mockFunction(
            locker, lockerMock, abi.encodeWithSelector(LockerMock.execTransactionFromModuleReturnData.selector)
        );

        /// Deploy BaseAccumulator Contract.
        accumulator = BaseAccumulator(_deployAccumulator());
        vm.prank(accumulator.governance());
        accumulator.transferGovernance(address(this));
        accumulator.acceptGovernance();

        // Set the accountant to a mock implementation
        address mockAccountant = address(new MockAccountant());
        vm.prank(BaseAccumulator(accumulator).governance());
        BaseAccumulator(accumulator).setAccountant(mockAccountant);

        BaseAccumulator.Split[] memory splits = new BaseAccumulator.Split[](2);
        splits[0] = BaseAccumulator.Split(treasuryRecipient, 5e16);
        splits[1] = BaseAccumulator.Split(liquidityFeeRecipient, 10e16);

        accumulator.setFeeSplit(splits);

        ILiquidityGauge.Reward memory rewardData = liquidityGauge.reward_data(address(rewardToken));

        vm.startPrank(liquidityGauge.admin());
        if (rewardData.distributor == address(0)) {
            liquidityGauge.add_reward(address(rewardToken), address(accumulator));
        } else {
            liquidityGauge.set_reward_distributor(address(rewardToken), address(accumulator));
        }

        if (rewardToken != strategyRewardToken) {
            rewardData = liquidityGauge.reward_data(address(strategyRewardToken));

            if (rewardData.distributor == address(0)) {
                liquidityGauge.add_reward(address(strategyRewardToken), address(accumulator));
            } else {
                liquidityGauge.set_reward_distributor(address(strategyRewardToken), address(accumulator));
            }
        }

        vm.stopPrank();

        vm.label(address(accumulator), "accumulator");
        vm.label(treasuryRecipient, "treasuryRecipient");
        vm.label(liquidityFeeRecipient, "liquidityFeeRecipient");
    }

    function _deployAccumulator() internal virtual returns (address payable) {}

    function test_setup() public view virtual {
        assertEq(accumulator.governance(), address(this));
        assertEq(accumulator.futureGovernance(), address(0));

        ILiquidityGauge.Reward memory rewardData = liquidityGauge.reward_data(address(rewardToken));
        assertEq(rewardData.distributor, address(accumulator));

        rewardData = liquidityGauge.reward_data(address(strategyRewardToken));
        assertEq(rewardData.distributor, address(accumulator));

        BaseAccumulator.Split[] memory splits = accumulator.getFeeSplit();

        assertEq(splits[0].receiver, treasuryRecipient);
        assertEq(splits[1].receiver, liquidityFeeRecipient);

        assertEq(splits[0].fee, 5e16); // 5%
        assertEq(splits[1].fee, 10e16); // 10%
    }

    function test_claimAll() public virtual {
        //Check Claimer recipient
        deal(address(rewardToken), address(this), 0);
        assertEq(rewardToken.balanceOf(address(this)), 0);
        //Check Dao recipient
        deal(address(rewardToken), address(treasuryRecipient), 0);
        assertEq(rewardToken.balanceOf(address(treasuryRecipient)), 0);
        //// Check Bounty recipient
        deal(address(rewardToken), address(liquidityFeeRecipient), 0);
        assertEq(rewardToken.balanceOf(address(liquidityFeeRecipient)), 0);
        //// Check lgv4
        uint256 gaugeBalanceBefore = rewardToken.balanceOf(address(liquidityGauge));

        accumulator.claimAndNotifyAll();

        uint256 treasury = rewardToken.balanceOf(address(treasuryRecipient));
        uint256 liquidityFee = rewardToken.balanceOf(address(liquidityFeeRecipient));
        uint256 gauge = rewardToken.balanceOf(address(liquidityGauge)) - gaugeBalanceBefore;
        uint256 claimer = rewardToken.balanceOf(address(this));

        /// WETH is distributed over 4 weeks to gauge.
        uint256 remaining = rewardToken.balanceOf(address(accumulator));
        uint256 total = treasury + liquidityFee + gauge + claimer + remaining;

        BaseAccumulator.Split[] memory feeSplit = accumulator.getFeeSplit();

        assertEq(total * accumulator.claimerFee() / 1e18, claimer);

        assertEq(total * feeSplit[0].fee / 1e18, treasury);
        assertEq(total * feeSplit[1].fee / 1e18, liquidityFee);

        skip(1 weeks);

        uint256 _before = ERC20(strategyRewardToken).balanceOf(address(liquidityGauge));

        deal(address(strategyRewardToken), address(accumulator), 1_000e18);
        accumulator.notifyReward(address(strategyRewardToken));

        /// It should distribute 1_000_000 PENDLE to LGV4, meaning no fees were taken.
        if (rewardToken != strategyRewardToken) {
            assertEq(ERC20(strategyRewardToken).balanceOf(address(liquidityGauge)), _before + 1_000e18);
        } else {
            uint256 _treasuryFee = (1_000e18 * uint256(feeSplit[0].fee)) / 1e18;

            uint256 _liquidityFee = (1_000e18 * uint256(feeSplit[1].fee)) / 1e18;

            uint256 _claimerFee = (1_000e18 * accumulator.claimerFee()) / 1e18;

            assertEq(ERC20(strategyRewardToken).balanceOf(address(treasuryRecipient)), treasury + _treasuryFee);
            assertEq(ERC20(strategyRewardToken).balanceOf(address(liquidityFeeRecipient)), liquidityFee + _liquidityFee);
            assertEq(
                ERC20(strategyRewardToken).balanceOf(address(liquidityGauge)),
                _before + 1_000e18 - _treasuryFee - _liquidityFee - _claimerFee
            );
        }
    }

    function test_setters() public {
        BaseAccumulator.Split[] memory splits = new BaseAccumulator.Split[](2);
        splits[0] = BaseAccumulator.Split(address(treasuryRecipient), 100);
        splits[1] = BaseAccumulator.Split(address(liquidityFeeRecipient), 50);

        accumulator.setFeeSplit(splits);

        splits = accumulator.getFeeSplit();

        assertEq(splits[0].receiver, address(treasuryRecipient));
        assertEq(splits[1].receiver, address(liquidityFeeRecipient));

        assertEq(splits[0].fee, 100);
        assertEq(splits[1].fee, 50);

        accumulator.setClaimerFee(1000e15);
        assertEq(accumulator.claimerFee(), 1000e15);

        accumulator.setFeeReceiver(address(1));
        assertEq(accumulator.feeReceiver(), address(1));

        vm.prank(address(2));
        vm.expectRevert(BaseAccumulator.GOVERNANCE.selector);
        accumulator.setFeeReceiver(address(2));
    }
}

contract LockerMock {
    function execTransactionFromModuleReturnData(address target, uint256 value, bytes memory data, uint8)
        external
        returns (bool success, bytes memory returnData)
    {
        (success, returnData) = target.call{value: value}(data);
        return (success, returnData);
    }
}

contract MockAccountant {
    function claimProtocolFees() external {}
}
