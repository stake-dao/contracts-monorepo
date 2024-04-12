// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Frax} from "address-book/protocols/252.sol";

import "src/frax/fxs/locker/FxsLockerFraxtal.sol";
import {IVestedFXS} from "src/base/interfaces/IVestedFXS.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

contract FXSLockerFraxtalTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    ERC20 private token = ERC20(Frax.FXS);
    FxsLockerFraxtal private locker;
    IVestedFXS private veToken = IVestedFXS(Frax.VEFXS);

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("fraxtal"));
        vm.selectFork(forkId);

        locker = new FxsLockerFraxtal(address(this), address(token), address(veToken));

        // Mint token to the Locker contract
        deal(address(token), address(locker), 100e18);
    }

    function test_initialization() public {
        assertEq(locker.name(), "FXS Locker");
        assertEq(locker.token(), address(token));
        assertEq(locker.veToken(), address(veToken));
    }

    function test_createLock() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        // 4 veFXS for every FXS locked for 4 years
        assertApproxEqRel(veToken.balanceOf(address(locker)), 100e18 * 4, 5e15);
    }

    function test_createMultiLockRevert() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        vm.expectRevert(FxsLockerFraxtal.LockAlreadyCreated.selector);
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);
    }

    function test_increaseAmount() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        /// Skip 7 days because veToken like veCRV rounds down to the nearest week
        skip(7 days);

        deal(address(token), address(locker), 100e18);
        locker.increaseLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18 * 4, 5e15);
    }

    function test_increaseAmountWithoutIncreaseTime() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        uint256 _end = IVestedFXS(veToken).lockedEnd(address(locker), 0);

        deal(address(token), address(locker), 100e18);
        locker.increaseLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18 * 4, 5e15);

        uint256 _newEnd = IVestedFXS(veToken).lockedEnd(address(locker), 0);
        assertEq(_newEnd, _end);
    }

    function test_increaseUnlockTime() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        uint256 _end = IVestedFXS(veToken).lockedEnd(address(locker), 0);

        skip(14 days);

        locker.increaseLock(0, block.timestamp + MAX_LOCK_DURATION);

        uint256 _newEnd = IVestedFXS(veToken).lockedEnd(address(locker), 0);
        assertEq(_newEnd, _end + 14 days);
    }

    function test_release() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        skip(block.timestamp + MAX_LOCK_DURATION + 1);
        assertEq(token.balanceOf(address(this)), 0);

        locker.release(address(this));
        assertEq(token.balanceOf(address(this)), 100e18);
    }

    function test_releaseBeforeEndRevert() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

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

    function test_setAccumulator() public {
        address newAccumulator = address(0x123);
        assertEq(locker.accumulator(), address(0));

        locker.setAccumulator(newAccumulator);
        assertEq(locker.accumulator(), newAccumulator);
    }

    function test_onlyGovernance() public {
        vm.startPrank(address(0x123));

        vm.expectRevert(VeCRVLocker.GOVERNANCE.selector);
        locker.execute(
            address(token), 0, abi.encodeWithSignature("approve(address,uint256)", address(veToken), type(uint256).max)
        );

        vm.expectRevert(VeCRVLocker.GOVERNANCE.selector);
        locker.setDepositor(address(0x123));

        vm.expectRevert(VeCRVLocker.GOVERNANCE.selector);
        locker.transferGovernance(address(0x123));

        vm.expectRevert(VeCRVLocker.GOVERNANCE_OR_DEPOSITOR.selector);
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        vm.expectRevert(VeCRVLocker.GOVERNANCE_OR_DEPOSITOR.selector);
        locker.increaseLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        vm.expectRevert(VeCRVLocker.GOVERNANCE.selector);
        locker.release(address(this));

        vm.stopPrank();
    }

    function test_execute() public {
        (bool success,) = locker.execute(
            address(token), 0, abi.encodeWithSignature("approve(address,uint256)", address(veToken), type(uint256).max)
        );
        assertTrue(success);

        (success,) = locker.execute(
            address(veToken),
            0,
            abi.encodeWithSignature(
                "createLock(address,uint256,uint128)", address(locker), 100e18, block.timestamp + MAX_LOCK_DURATION
            )
        );
        assertTrue(success);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 100e18 * 4, 5e15);
    }
}
