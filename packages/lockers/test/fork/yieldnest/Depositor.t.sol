// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/BaseTest.t.sol";

import {DAO} from "address-book/src/DaoEthereum.sol";
import {CommonUniversal} from "address-book/src/CommonUniversal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldnestProtocol, YieldnestLocker} from "address-book/src/YieldnestEthereum.sol";

import {ISafe} from "src/interfaces/ISafe.sol";
import {IPreLaunchLocker} from "src/interfaces/IPreLaunchLocker.sol";
import {YieldnestDepositor, IYieldNest} from "src/integrations/yieldnest/Depositor.sol";

contract YieldNestDepositorTest is BaseTest {
    YieldnestDepositor public depositor;

    address internal constant LOCKER = YieldnestLocker.LOCKER;
    address internal constant SDYND = YieldnestLocker.SDYND;
    address internal constant SDYND_GAUGE = YieldnestLocker.GAUGE;
    address internal constant PRELAUNCH = YieldnestLocker.PRELAUNCH_LOCKER;

    address internal constant YND = YieldnestProtocol.YND;
    address internal constant VEYND = YieldnestProtocol.VEYND;
    address internal constant ESCROW = YieldnestProtocol.ESCROW;

    address internal constant CLOCK = 0xA52965bb24021bA649f3c23b74A8Fb064BE07950;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        depositor = new YieldnestDepositor({
            _token: YND,
            _locker: LOCKER,
            _minter: SDYND,
            _gauge: SDYND_GAUGE,
            _gateway: LOCKER
        });

        vm.prank(LOCKER);
        ISafe(LOCKER).enableModule(address(depositor));

        vm.prank(LOCKER);
        ISafe(LOCKER).setFallbackHandler(CommonUniversal.SAFE_FALLBACK_HANDLER);
    }

    function test_setDepositorInPrelaunchLocker() public {
        uint256 interval = IYieldNest(CLOCK).epochNextCheckpointTs();

        /// Warp to 1 hour before the next checkpoint
        vm.warp(interval - 1 hours);

        /// Snapshot the balance of the PRELAUNCH contract
        uint256 balance = IERC20(YND).balanceOf(address(PRELAUNCH));

        vm.prank(DAO.GOVERNANCE);
        IPreLaunchLocker(PRELAUNCH).lock(address(depositor));

        /// Assert that the balance of the PRELAUNCH contract is 0
        assertEq(IERC20(YND).balanceOf(address(PRELAUNCH)), 0);

        uint256[] memory tokenIds = depositor.getTokenIds();
        assertEq(tokenIds.length, 1);

        uint256 tokenId = tokenIds[0];
        IYieldNest.LockedBalance memory lockedBalance = IYieldNest(ESCROW).locked(tokenId);

        assertEq(lockedBalance.amount, balance);
        assertEq(lockedBalance.start, block.timestamp / 1 weeks * 1 weeks + 1 weeks);

        address user = address(this);
        deal(YND, address(user), 1000e18);

        vm.prank(address(user));
        IERC20(YND).approve(address(depositor), 1000e18);

        vm.prank(address(user));
        depositor.depositAll({_lock: true, _stake: false, _user: address(user)});

        tokenIds = depositor.getTokenIds();
        assertEq(tokenIds.length, 1);

        assertEq(IERC20(SDYND).balanceOf(address(user)), 1000e18);
        assertEq(IERC20(YND).balanceOf(address(LOCKER)), 1000e18);

        uint256 nextInterval = IYieldNest(CLOCK).epochNextCheckpointTs() + 1 weeks;
        uint256 preCheckpointWindow = depositor.preCheckpointWindow();

        vm.warp(nextInterval - preCheckpointWindow);

        deal(YND, address(user), 1000e18);

        vm.prank(address(user));
        IERC20(YND).approve(address(depositor), 1000e18);

        vm.prank(address(user));
        depositor.depositAll({_lock: true, _stake: false, _user: address(user)});

        assertEq(IERC20(SDYND).balanceOf(address(user)), 2000e18);
        assertEq(IERC20(YND).balanceOf(address(LOCKER)), 0);

        tokenIds = depositor.getTokenIds();
        assertEq(tokenIds.length, 2);

        tokenId = tokenIds[1];
        lockedBalance = IYieldNest(ESCROW).locked(tokenId);

        assertEq(lockedBalance.amount, 2000e18);
        assertEq(lockedBalance.start, nextInterval);
    }

    function test_setPreCheckpointWindow() public {
        uint256 preCheckpointWindow = depositor.preCheckpointWindow();
        assertEq(preCheckpointWindow, 12 hours);

        depositor.setPreCheckpointWindow(1 hours);

        assertEq(depositor.preCheckpointWindow(), 1 hours);
    }

    function getTokenLocked(uint256 tokenId) public view returns (uint256) {
        IYieldNest.LockedBalance memory lockedBalance = IYieldNest(ESCROW).locked(tokenId);
        return lockedBalance.amount;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }
}
