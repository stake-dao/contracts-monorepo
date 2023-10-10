// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/fx/locker/FXNLocker.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {IVeToken} from "src/base/interfaces/IVeToken.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ISmartWalletChecker} from "src/base/interfaces/ISmartWalletChecker.sol";

interface ILido {
    function submit(address _referral) external payable;
}

contract FXNLockerTest is Test {
    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    IERC20 private token;
    FXNLocker private locker;
    IVeToken private veToken;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.rpcUrl("ethereum"), 18_227_675);
        vm.selectFork(forkId);

        token = IERC20(AddressBook.FXN);
        veToken = IVeToken(AddressBook.VE_FXN);

        locker = new FXNLocker(address(this), address(token), address(veToken));

        // Whitelist the locker contract
        vm.prank(ISmartWalletChecker(AddressBook.FXN_SMART_WALLET_CHECKER).owner());
        ISmartWalletChecker(AddressBook.FXN_SMART_WALLET_CHECKER).approveWallet(address(locker));

        // Mint token to the Locker contract
        deal(address(token), address(locker), 100e18);
    }

    function test_initialization() public {
        assertEq(locker.name(), "FXN Locker");
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

        uint256 _end = IVeToken(veToken).locked__end(address(locker));

        deal(address(token), address(locker), 100e18);
        locker.increaseLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        assertApproxEqRel(veToken.balanceOf(address(locker)), 200e18, 5e15);

        uint256 _newEnd = IVeToken(veToken).locked__end(address(locker));
        assertEq(_newEnd, _end);
    }

    function test_increaseUnlockTime() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        uint256 _end = IVeToken(veToken).locked__end(address(locker));

        skip(14 days);

        locker.increaseLock(0, block.timestamp + MAX_LOCK_DURATION);

        uint256 _newEnd = IVeToken(veToken).locked__end(address(locker));
        assertEq(_newEnd, _end + 14 days);
    }

    function test_claimRewards() public {
        locker.createLock(100e18, block.timestamp + MAX_LOCK_DURATION);

        skip(7 days);

        /// stETH.
        address _rewardToken = IFeeDistributor(AddressBook.FXN_FEE_DISTRIBUTOR).token();

        /// Deal to Fee Distributor.
        ILido(_rewardToken).submit{value: 100e18}(address(this));
        IERC20(_rewardToken).transfer(AddressBook.FXN_FEE_DISTRIBUTOR, 100e18);
        assertEq(IERC20(_rewardToken).balanceOf(address(this)), 0);

        IFeeDistributor(AddressBook.FXN_FEE_DISTRIBUTOR).checkpoint_token();
        skip(7 days);

        locker.claimRewards(AddressBook.FXN_FEE_DISTRIBUTOR, _rewardToken, address(this));
        assertApproxEqRel(IERC20(_rewardToken).balanceOf(address(this)), 100e18, 1e15);
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
        locker.execute(
            address(token), 0, abi.encodeWithSignature("approve(address,uint256)", address(veToken), type(uint256).max)
        );

        locker.execute(
            address(veToken),
            0,
            abi.encodeWithSignature("create_lock(uint256,uint256)", 100e18, block.timestamp + MAX_LOCK_DURATION)
        );

        assertApproxEqRel(veToken.balanceOf(address(locker)), 100e18, 5e15);
    }
}
