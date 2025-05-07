// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.19 <0.9.0;

import {BaseAccumulator} from "src/common/accumulator/BaseAccumulator.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {Test} from "forge-std/src/Test.sol";
import {BaseAccumulatorHarness} from "test/unit/BaseAccumulator/utils/BaseAccumulatorHarness.sol";

contract BaseAccumulatorTest is Test {
    BaseAccumulatorHarness internal baseAccumulator;
    MockERC20 internal rewardToken;

    address internal governance;
    MockLiquidityGauge internal gauge;
    MockLocker internal locker;
    MockAccountant internal accountant;
    MockFeeReceiver internal feeReceiver;

    function setUp() public virtual {
        // set the governance
        governance = makeAddr("governance");

        // deploy the reward token
        rewardToken = new MockERC20();
        rewardToken.initialize("Wrapped Ether ", "WETH", 18);

        // deploy gauge, locker, accountant and fee receiver contracts
        gauge = new MockLiquidityGauge();
        locker = new MockLocker();
        accountant = new MockAccountant();
        feeReceiver = new MockFeeReceiver();

        // deploy the accumulator
        baseAccumulator = new BaseAccumulatorHarness(address(gauge), address(rewardToken), address(locker), governance);

        // approve the reward token for the accumulator
        vm.prank(governance);
        baseAccumulator.approveNewTokenReward(address(rewardToken));
    }
}

contract MockLiquidityGauge {
    function deposit_reward_token(address token, uint256 amount) external {
        MockERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}

contract MockLocker {}

contract MockAccountant {
    function claimProtocolFees() external {}
}

contract MockFeeReceiver {
    function split(address token) external {}
}
