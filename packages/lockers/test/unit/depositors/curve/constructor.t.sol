// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {Curve} from "address-book/src/protocols/1.sol";
import {CRV} from "address-book/src/lockers/1.sol";
import {MockERC20} from "forge-std/src/mocks/MockERC20.sol";
import {CurveDepositor} from "src/mainnet/curve/Depositor.sol";
import {DepositorTest} from "test/unit/depositors/DepositorTest.t.sol";

contract CurveDepositor__constructor is DepositorTest {
    function test_SetsTheGivenToken(address _token) external {
        // it sets the given token

        vm.assume(_token != address(0));

        CurveDepositor _depositor =
            new CurveDepositor(_token, makeAddr("locker"), minter, makeAddr("gauge"), makeAddr("gateway"));
        assertEq(_depositor.token(), _token);
    }

    function test_SetsTheGivenLocker(address _locker) external {
        // it sets the given locker

        vm.assume(_locker != address(0));

        CurveDepositor _depositor =
            new CurveDepositor(makeAddr("token"), _locker, minter, makeAddr("gauge"), makeAddr("gateway"));
        assertEq(_depositor.locker(), _locker);
    }

    function test_SetsTheGivenMinter(bytes32 salt) external {
        // it sets the given minter

        MockERC20 _minter = new MockERC20{salt: salt}();
        _minter.initialize("Minter Token", "MT", 18);
        // minter = address(minterMock);

        CurveDepositor _depositor = new CurveDepositor(
            makeAddr("token"), makeAddr("locker"), address(_minter), makeAddr("gauge"), makeAddr("gateway")
        );
        assertEq(_depositor.minter(), address(_minter));
    }

    function test_SetsTheGivenGauge(address _gauge) external {
        // it sets the given gauge

        vm.assume(_gauge != address(0));

        CurveDepositor _depositor =
            new CurveDepositor(makeAddr("token"), makeAddr("locker"), minter, _gauge, makeAddr("gateway"));
        assertEq(_depositor.gauge(), _gauge);
    }

    function test_SetsTheGivenGateway(address _gateway) external {
        // it sets the given gateway

        vm.assume(_gateway != address(0));

        CurveDepositor _depositor =
            new CurveDepositor(makeAddr("token"), makeAddr("locker"), minter, makeAddr("gauge"), _gateway);
        assertEq(_depositor.GATEWAY(), _gateway);
    }

    function test_Sets4YearsAsTheMaxLockDuration() external view {
        // it sets 4 years as the max lock duration

        assertEq(CurveDepositor(depositor).MAX_LOCK_DURATION(), 4 * 365 days);
    }

    function test_SetsTheExpectedVeToken() external view {
        // it sets the expected veToken

        assertEq(CurveDepositor(depositor).VE_CRV(), Curve.VECRV);
    }

    constructor() DepositorTest(Curve.CRV, Curve.VECRV, CRV.GAUGE) {}

    function _deployDepositor() internal override returns (address) {
        return address(new CurveDepositor(token, locker, minter, gauge, locker));
    }
}
