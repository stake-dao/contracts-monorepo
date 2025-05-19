// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BalancerLocker, BalancerProtocol} from "address-book/src/BalancerEthereum.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {BalancerDepositor} from "src/mainnet/balancer/Depositor.sol";
import {DepositorTest} from "test/unit/depositors/DepositorTest.t.sol";

contract BalancerDepositor__constructor is DepositorTest {
    constructor() DepositorTest(BalancerProtocol.BAL, BalancerProtocol.VEBAL, BalancerLocker.GAUGE) {}

    function test_SetsTheGivenToken(address _token) external {
        // it sets the given token

        vm.assume(_token != address(0));

        BalancerDepositor _depositor =
            new BalancerDepositor(_token, makeAddr("locker"), minter, makeAddr("gauge"), makeAddr("gateway"));
        assertEq(_depositor.token(), _token);
    }

    function test_SetsTheGivenLocker(address _locker) external {
        // it sets the given locker

        vm.assume(_locker != address(0));

        BalancerDepositor _depositor =
            new BalancerDepositor(makeAddr("token"), _locker, minter, makeAddr("gauge"), makeAddr("gateway"));
        assertEq(_depositor.locker(), _locker);
    }

    function test_SetsTheGivenMinter(bytes32 salt) external {
        // it sets the given minter

        MockERC20 _minter = new MockERC20{salt: salt}();
        _minter.initialize("Minter Token", "MT", 18);
        // minter = address(minterMock);

        BalancerDepositor _depositor = new BalancerDepositor(
            makeAddr("token"), makeAddr("locker"), address(_minter), makeAddr("gauge"), makeAddr("gateway")
        );
        assertEq(_depositor.minter(), address(_minter));
    }

    function test_SetsTheGivenGauge(address _gauge) external {
        // it sets the given gauge

        vm.assume(_gauge != address(0));

        BalancerDepositor _depositor =
            new BalancerDepositor(makeAddr("token"), makeAddr("locker"), minter, _gauge, makeAddr("gateway"));
        assertEq(_depositor.gauge(), _gauge);
    }

    function test_SetsTheGivenGateway(address _gateway) external {
        // it sets the given gateway

        vm.assume(_gateway != address(0));

        BalancerDepositor _depositor =
            new BalancerDepositor(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), _gateway);
        assertEq(_depositor.GATEWAY(), _gateway);
    }

    function test_Sets1YearAsTheMaxLockDuration() external view {
        // it sets 1 year as the max lock duration

        assertEq(BalancerDepositor(depositor).MAX_LOCK_DURATION(), 364 * 86_400);
    }

    function test_SetsTheExpectedVeToken() external view {
        // it sets the expected veToken

        assertEq(BalancerDepositor(depositor).VE_BAL(), BalancerProtocol.VEBAL);
    }

    function _deployDepositor() internal override returns (address) {
        return address(new BalancerDepositor(token, locker, minter, gauge, locker));
    }
}
