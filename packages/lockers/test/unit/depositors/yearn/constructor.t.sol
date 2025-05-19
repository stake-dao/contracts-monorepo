// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {YearnLocker, YearnProtocol} from "address-book/src/YearnEthereum.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {YearnDepositor} from "src/mainnet/yearn/Depositor.sol";
import {DepositorTest} from "test/unit/depositors/DepositorTest.t.sol";

contract YearnDepositor__constructor is DepositorTest {
    function test_SetsTheGivenToken(address _token) external {
        // it sets the given token

        vm.assume(_token != address(0));

        YearnDepositor _depositor =
            new YearnDepositor(_token, makeAddr("locker"), minter, makeAddr("gauge"), makeAddr("gateway"));
        assertEq(_depositor.token(), _token);
    }

    function test_SetsTheGivenLocker(address _locker) external {
        // it sets the given locker

        vm.assume(_locker != address(0));

        YearnDepositor _depositor =
            new YearnDepositor(makeAddr("token"), _locker, minter, makeAddr("gauge"), makeAddr("gateway"));
        assertEq(_depositor.locker(), _locker);
    }

    function test_SetsTheGivenMinter(bytes32 salt) external {
        // it sets the given minter

        MockERC20 _minter = new MockERC20{salt: salt}();
        _minter.initialize("Minter Token", "MT", 18);
        // minter = address(minterMock);

        YearnDepositor _depositor = new YearnDepositor(
            makeAddr("token"), makeAddr("locker"), address(_minter), makeAddr("gauge"), makeAddr("gateway")
        );
        assertEq(_depositor.minter(), address(_minter));
    }

    function test_SetsTheGivenGauge(address _gauge) external {
        // it sets the given gauge

        vm.assume(_gauge != address(0));

        YearnDepositor _depositor =
            new YearnDepositor(makeAddr("token"), makeAddr("locker"), minter, _gauge, makeAddr("gateway"));
        assertEq(_depositor.gauge(), _gauge);
    }

    function test_SetsTheGivenGateway(address _gateway) external {
        // it sets the given gateway

        vm.assume(_gateway != address(0));

        YearnDepositor _depositor =
            new YearnDepositor(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), _gateway);
        assertEq(_depositor.GATEWAY(), _gateway);
    }

    function test_SetsTheExpectedMaxLockDuration() external view {
        // it sets the expected max lock duration

        assertEq(YearnDepositor(depositor).MAX_LOCK_DURATION(), 4 * 370 days);
    }

    function test_SetsTheExpectedVeToken() external view {
        // it sets the expected veToken

        assertEq(YearnDepositor(depositor).VE_YFI(), YearnProtocol.VEYFI);
    }

    constructor() DepositorTest(YearnProtocol.YFI, YearnProtocol.VEYFI, YearnLocker.GAUGE) {}

    function _deployDepositor() internal override returns (address) {
        return address(new YearnDepositor(token, locker, minter, gauge, locker));
    }
}
