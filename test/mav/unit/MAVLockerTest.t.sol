// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/mav/locker/MAVLocker.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IVotingEscrowMav} from "src/base/interfaces/IVotingEscrowMav.sol";

address constant MAV_ETH = AddressBook.MAV;
address constant MAV_BASE = 0x64b88c73A5DfA78D1713fE1b4c69a22d7E0faAa7;
address constant MAV_BNB = 0xd691d9a68C887BDF34DA8c36f63487333ACfD103;
address constant MAV_ZKSYNC = 0x787c09494Ec8Bcb24DcAf8659E7d5D69979eE508; 

address constant VE_MAV_ETH = AddressBook.VE_MAV;
address constant VE_MAV_BASE = 0xFcCB5263148fbF11d58433aF6FeeFF0Cc49E0EA5;
address constant VE_MAV_BNB = 0xE6108f1869d37E5076a56168C66A1607EdB10819;
address constant VE_MAV_ZKSYNC = 0x7EDcB053d4598a145DdaF5260cf89A32263a2807;

abstract contract MAVLockerTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    IERC20 private token;
    MAVLocker private locker;
    IVotingEscrowMav private veToken;
    string private chainAlias;

    constructor(address _mav, address _veMav, string memory _chainAlias) {
        token = IERC20(_mav);
        veToken = IVotingEscrowMav(_veMav);
        chainAlias = _chainAlias;
    }

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl(chainAlias));
        vm.selectFork(forkId);
        locker = new MAVLocker(address(this), address(token), address(veToken));

        // Mint MAV to the MAVLocker contract
        deal(address(token), address(locker), 100e18);
    }

    function test_initialization() public {
        emit log_string(vm.envString("RPC_URL_MAINNET"));
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

        vm.expectRevert(VeMAVLocker.LOCK_ALREADY_EXISTS.selector);
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

        vm.expectRevert(VeMAVLocker.GOVERNANCE.selector);
        locker.execute(
            address(token), 0, abi.encodeWithSignature("approve(address,uint256)", address(veToken), type(uint256).max)
        );

        vm.expectRevert(VeMAVLocker.GOVERNANCE.selector);
        locker.setDepositor(address(0x123));

        vm.expectRevert(VeMAVLocker.GOVERNANCE.selector);
        locker.transferGovernance(address(0x123));

        vm.expectRevert(VeMAVLocker.GOVERNANCE.selector);
        locker.createLock(100e18, MAX_LOCK_DURATION);

        vm.expectRevert(VeMAVLocker.GOVERNANCE_OR_DEPOSITOR.selector);
        locker.increaseLock(100e18, MAX_LOCK_DURATION);

        vm.expectRevert(VeMAVLocker.GOVERNANCE.selector);
        locker.release(address(this));

        vm.stopPrank();
    }

    function test_execute() public {
        /// Create a lock using execute function.
        (uint256 expectedBalance,) = veToken.previewPoints(100e18, MAX_LOCK_DURATION);

        locker.execute(
            address(token), 0, abi.encodeWithSignature("approve(address,uint256)", address(veToken), type(uint256).max)
        );

        locker.execute(
            address(veToken),
            0,
            abi.encodeWithSignature("stake(uint256,uint256,address)", 100e18, MAX_LOCK_DURATION, address(locker))
        );

        assertEq(veToken.balanceOf(address(locker)), expectedBalance);
    }
}

contract MAVLockerTestEth is MAVLockerTest(MAV_ETH, VE_MAV_ETH, "ethereum") {}
contract MAVLockerTestBase is MAVLockerTest(MAV_BASE, VE_MAV_BASE, "base") {}
contract MAVLockerTestBnb is MAVLockerTest(MAV_BNB, VE_MAV_BNB, "bnb") {}