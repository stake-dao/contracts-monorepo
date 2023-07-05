// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/mav/locker/MAVLocker.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IVotingEscrowMav} from "src/base/interfaces/IVotingEscrowMav.sol";

contract MAVLockerTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    IERC20 private token;
    MAVLocker private locker;
    IVotingEscrowMav private veToken;

    function setUp() public virtual {
        token = IERC20(AddressBook.MAV);
        veToken = IVotingEscrowMav(AddressBook.VE_MAV);

        locker = new MAVLocker(address(this), address(token), address(veToken));

        // Mint MAV to the MAVLocker contract
        deal(address(token), address(locker), 100e18);
    }

    function test_initialization() public {
        assertEq(locker.name(), "MAV Locker");
        assertEq(locker.token(), address(token));
        assertEq(locker.veToken(), address(veToken));
    }

    function test_createLock() public {
        (uint256 expectedBalance,) = veToken.previewPoints(100e18, MAX_LOCK_DURATION);
        locker.createLock(100e18, MAX_LOCK_DURATION);

        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
    }

    function test_createMultipleLocksRevert() public {
        locker.createLock(100e18, MAX_LOCK_DURATION);

        vm.expectRevert(MAVLocker.LOCK_ALREADY_EXISTS.selector);
        locker.createLock(100e18, MAX_LOCK_DURATION);
    }

    function test_increaseAmount() public {
        locker.createLock(100e18, MAX_LOCK_DURATION);

        (uint256 expectedBalance,) = veToken.previewPoints(100e18, MAX_LOCK_DURATION);

        /// Just need to skip 1 second to make sure the timestamp is different
        skip(1);

        deal(address(token), address(locker), 100e18);
        locker.increaseLock(100e18, MAX_LOCK_DURATION);

        (uint256 newExpectedBalance,) = veToken.previewPoints(200e18, MAX_LOCK_DURATION);

        assertGt(newExpectedBalance, expectedBalance);
        assertEq(veToken.balanceOf(address(locker)), newExpectedBalance);
    }

    function test_release() public {
        locker.createLock(100e18, MAX_LOCK_DURATION);

        skip(MAX_LOCK_DURATION + 1);
        assertEq(token.balanceOf(address(this)), 0);

        locker.release(address(this));
        assertEq(token.balanceOf(address(this)), 100e18);
    }

    function test_releaseBeforeEndRevert() public {
        locker.createLock(100e18, MAX_LOCK_DURATION);

        vm.expectRevert();
        locker.release(address(this));
    }

    function test_transferGovernance() public {
        address newGovernance = address(0x123);

        locker.transferGovernance(newGovernance);

        assertEq(locker.governance(), address(this));
        assertEq(locker.futureGovernance(), newGovernance);

        vm.prank(newGovernance);
        locker.acceptGovernance();

        assertEq(locker.governance(), newGovernance);
        assertEq(locker.futureGovernance(), newGovernance);
    }

    function test_transferGovernanceWrongCallerRevert() public {
        address newGovernance = address(0x123);

        locker.transferGovernance(newGovernance);

        vm.expectRevert();
        locker.acceptGovernance();
    }

    function test_setDepositor() public {
        address newDepositor = address(0x123);
        assertEq(locker.depositor(), address(0));

        locker.setDepositor(newDepositor);
        assertEq(locker.depositor(), newDepositor);
    }

    function test_onlyGovernance() public {
        vm.startPrank(address(0x123));

        vm.expectRevert(MAVLocker.GOVERNANCE.selector);
        locker.execute(address(token), 0, abi.encodeWithSignature("approve(address,uint256)", address(veToken), type(uint256).max));

        vm.expectRevert(MAVLocker.GOVERNANCE.selector);
        locker.setDepositor(address(0x123));

        vm.expectRevert(MAVLocker.GOVERNANCE.selector);
        locker.transferGovernance(address(0x123));

        vm.expectRevert(MAVLocker.GOVERNANCE.selector);
        locker.createLock(100e18, MAX_LOCK_DURATION);

        vm.expectRevert(MAVLocker.GOVERNANCE_OR_DEPOSITOR.selector);
        locker.increaseLock(100e18, MAX_LOCK_DURATION);

        vm.expectRevert(MAVLocker.GOVERNANCE.selector);
        locker.release(address(this));

        vm.stopPrank();
    }

    function test_execute() public {
        /// Create a lock using execute function.
        (uint256 expectedBalance,) = veToken.previewPoints(100e18, MAX_LOCK_DURATION);

        locker.execute(
            address(token),
            0,
            abi.encodeWithSignature("approve(address,uint256)", address(veToken), type(uint256).max)
        );

        locker.execute(
            address(veToken),
            0,
            abi.encodeWithSignature("stake(uint256,uint256,address)", 100e18, MAX_LOCK_DURATION, address(locker))
        );

        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
    }

}
