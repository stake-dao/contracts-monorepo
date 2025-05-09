// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {Test} from "forge-std/src/Test.sol";
import {YearnAccumulator} from "src/mainnet/yearn/Accumulator.sol";
import {Test} from "forge-std/src/Test.sol";
import {DAO} from "address-book/src/dao/1.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";

abstract contract AccumulatorTest is Test {
    address payable internal accumulator;

    // etched addresses
    address internal token;
    address internal rewardToken;
    address internal governance;

    // mock addresses
    address internal gauge;
    address internal locker;
    address internal accountant;
    address internal feeReceiver;

    constructor(address _token, address _rewardToken, address _gauge) {
        // set the governance
        governance = DAO.GOVERNANCE;

        // deploy the protocol token at the address of the expected protocol token
        MockERC20 mockToken = new MockERC20();
        mockToken.initialize("Token Name", "TKN", 18);
        vm.etch(_token, address(mockToken).code);
        token = _token;

        // deploy the reward token at the address of the expected reward token
        MockERC20 mockRewardToken = new MockERC20();
        mockRewardToken.initialize("Reward Token", "rTKN", 18);
        vm.etch(_rewardToken, address(mockRewardToken).code);
        rewardToken = _rewardToken;

        // deploy gauge mock at the address of the expected gauge
        MockLiquidityGauge mockGauge = new MockLiquidityGauge();
        vm.etch(_gauge, address(mockGauge).code);
        gauge = _gauge;

        // deploy locker, accountant and fee receiver mocks
        locker = address(new MockLocker());
        accountant = address(new MockAccountant());
        feeReceiver = address(new MockFeeReceiver());

        // label the important addresses
        vm.label(token, "Token");
        vm.label(rewardToken, "Reward Token");
        vm.label(gauge, "Gauge");
        vm.label(locker, "Locker");
        vm.label(accountant, "Accountant");
        vm.label(feeReceiver, "Fee Receiver");
        vm.label(governance, "Governance");
        vm.label(accumulator, "Accumulator");
    }

    function setUp() public virtual {
        // deploy the accumulator
        accumulator = payable(_deployAccumulator());

        // set the accountant
        vm.prank(governance);
        YearnAccumulator(accumulator).setAccountant(accountant);
    }

    // @dev must be implemented by the test contract
    function _deployAccumulator() internal virtual returns (address) {}
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
