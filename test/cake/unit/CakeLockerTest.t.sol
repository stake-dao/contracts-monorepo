// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CakeLocker} from "src/cake/locker/CakeLocker.sol";
import {VeCRVLocker} from "src/base/locker/VeCRVLocker.sol";
import {IVeToken} from "src/base/interfaces/IVeToken.sol";
import {IVeCake} from "src/base/interfaces/IVeCake.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

interface ICakeWhitelist {
    function setWhitelistedCallers(address[] memory callers, bool ok) external;
    function owner() external view returns (address);
}

contract CakeLockerTest is Test {
    uint256 private constant MAX_LOCK_DURATION = (209 * 1 weeks) - 1;

    ERC20 private token;
    CakeLocker private locker;
    IVeToken private veToken;

    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant VE_CAKE = 0x5692DB8177a81A6c6afc8084C2976C9933EC1bAB;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("bnb"), 33_702_400);
        vm.selectFork(forkId);

        token = ERC20(CAKE);
        veToken = IVeToken(VE_CAKE);

        locker = new CakeLocker(address(this), address(token), address(veToken));

        // Whitelist the locker contract
        vm.prank(ICakeWhitelist(VE_CAKE).owner());
        address[] memory callers = new address[](1);
        callers[0] = address(locker);
        ICakeWhitelist(VE_CAKE).setWhitelistedCallers(callers, true);

        // Mint token to the Locker contract
        deal(address(token), address(locker), 200e18);
    }

    function test_initialization() public {
        assertEq(locker.name(), "veCAKE Locker");
        assertEq(locker.token(), address(token));
        assertEq(locker.veToken(), address(veToken));
    }

    function test_createLock() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 100e18, 5e15);
    }

    function test_increaseAmount() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        /// Skip 7 days because veToken like veCRV rounds down to the nearest week
        skip(7 days);

        deal(address(token), address(locker), 100e18);
        locker.increaseLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18, 5e15);
    }

    function test_increaseAmountWithoutIncreaseTime() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        (, uint256 _end,,,,,,) = IVeCake(address(veToken)).getUserInfo(address(locker));
        deal(address(token), address(locker), 100e18);
        locker.increaseLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18, 5e15);

        (, uint256 _newEnd,,,,,,) = IVeCake(address(veToken)).getUserInfo(address(locker));
        assertEq(_newEnd, _end);
    }

    function test_increaseUnlockTime() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        (, uint256 _end,,,,,,) = IVeCake(address(veToken)).getUserInfo(address(locker));

        skip(14 days);

        locker.increaseLock(0, block.timestamp + MAX_LOCK_DURATION);

        (, uint256 _newEnd,,,,,,) = IVeCake(address(veToken)).getUserInfo(address(locker));
        assertEq(_newEnd, _end + 14 days);
    }

    function test_increaseAmountAndIncreaseTime() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        (, uint256 _end,,,,,,) = IVeCake(address(veToken)).getUserInfo(address(locker));
        deal(address(token), address(locker), 100e18);
        locker.increaseLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18, 5e15);

        (, uint256 _newEnd,,,,,,) = IVeCake(address(veToken)).getUserInfo(address(locker));
        assertEq(_newEnd, _end);
    }

    function test_release() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        skip(MAX_LOCK_DURATION + 1 weeks);

        assertEq(token.balanceOf(address(this)), 0);

        locker.release(address(this));
        assertEq(token.balanceOf(address(this)), 100e18);
    }

    function test_EarlyReleaseAfterEndRevert() public {
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
        locker.execute(
            address(token), 0, abi.encodeWithSignature("approve(address,uint256)", address(veToken), type(uint256).max)
        );

        locker.execute(
            address(veToken),
            0,
            abi.encodeWithSignature("createLock(uint256,uint256)", 100e18, block.timestamp + MAX_LOCK_DURATION)
        );

        assertApproxEqRel(veToken.balanceOf(address(locker)), 100e18, 5e15);
    }
}
