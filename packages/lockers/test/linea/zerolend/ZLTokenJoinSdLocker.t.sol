// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import {BaseZeroLendTokenTest} from "test/linea/zerolend/common/BaseZeroLendTokenTest.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {ILocker as ISdLocker} from "src/common/interfaces/ILocker.sol";
import {IDepositor} from "src/common/interfaces/IDepositor.sol";
import {IZeroVp} from "src/common/interfaces/zerolend/zerolend/IZeroVp.sol";
import {ISdZeroLocker} from "src/common/interfaces/zerolend/stakedao/ISdZeroLocker.sol";
import {ISdZeroDepositor} from "src/common/interfaces/zerolend/stakedao/ISdZeroDepositor.sol";
import {IZeroLocker} from "src/common/interfaces/zerolend/zerolend/IZeroLocker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// end to end tests for the ZeroLend integration
contract ZeroLendTest is BaseZeroLendTokenTest {
    constructor() {}

    address userWithStakedNft = 0xB50C52FA0f34587063563321dc1c28Bc98bd8237;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("linea"), 14_369_758);
        vm.selectFork(forkId);

        _deployZeroIntegration();

        // Offset the creating vs the actual test
        vm.warp(block.timestamp + 30 days);
    }

    function _getLockedDetails(address _user)
        internal
        view
        returns (uint256[] memory _tokenIds, uint256 _amount, uint256 _power)
    {
        (uint256[] memory tempTokenIds, IZeroVp.LockedBalance[] memory _lockedBalances) =
            IZeroVp(address(veZero)).getLockedNftDetails(_user);

        _tokenIds = tempTokenIds;

        for (uint256 index = 0; index < _lockedBalances.length; index++) {
            _amount += _lockedBalances[index].amount;
            _power += _lockedBalances[index].power;
        }
    }

    function _getLockerStartEndTime(address _locker) internal view returns (uint256 _start, uint256 _end) {
        (, IZeroVp.LockedBalance[] memory _lockedBalances) = IZeroVp(address(veZero)).getLockedNftDetails(_locker);

        require(_lockedBalances.length == 1);

        _end = _lockedBalances[0].end;
        _start = _lockedBalances[0].start;
    }

    function test_canJoinSdWithOldZeroLendLock() public {
        vm.startPrank(userWithStakedNft);

        // make sure the user doesn't have unstaked tokens
        assertEq(IZeroLocker(zeroLockerToken).balanceOf(userWithStakedNft), 0);

        (uint256[] memory _tokenIds, uint256 totalUserLockedAmount,) = _getLockedDetails(userWithStakedNft);
        (, uint256 totalSdLockedAmount,) = _getLockedDetails(locker);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IZeroVp(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // userWithStakedNft should have 0 sdToken before joining
        assertEq(IERC20(sdToken).balanceOf(userWithStakedNft), 0);

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        ISdZeroDepositor(address(depositor)).deposit(_tokenIds, true, userWithStakedNft);

        // ## test everything

        // locked amount of user was transfered to stake dao
        (, uint256 afterTotalSdLockedAmount, uint256 afterTotalSdPower) = _getLockedDetails(locker);
        assertEq(afterTotalSdLockedAmount, totalUserLockedAmount + totalSdLockedAmount);

        // since the user had an end date lower than 4 years and we rebased it
        // with the locker token when merging, we should have a larger total power
        (uint256 _start, uint256 _end) = _getLockerStartEndTime(locker);
        uint256 _diff = _end - _start;
        uint256 expectedNewPower = _diff * (totalSdLockedAmount + totalUserLockedAmount) / (4 * 365 * 24 * 3600);
        assertEq(afterTotalSdPower, expectedNewPower);

        // user doens't own any NFT and has no locks
        assertEq(IZeroLocker(zeroLockerToken).balanceOf(userWithStakedNft), 0);
        (uint256[] memory _afterTokenIds,) = IZeroVp(address(veZero)).getLockedNftDetails(userWithStakedNft);
        assertEq(_afterTokenIds.length, 0);

        assertEq(IERC20(sdToken).balanceOf(userWithStakedNft), 0);
        assertEq(liquidityGauge.balanceOf(userWithStakedNft) > 0, true);
    }

    function test_cantJoinSdMultipleTimes() public {
        vm.startPrank(userWithStakedNft);

        // make sure the user doesn't have unstaked tokens
        assertEq(IZeroLocker(zeroLockerToken).balanceOf(userWithStakedNft), 0);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IZeroVp(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        ISdZeroDepositor(address(depositor)).deposit(_tokenIds, true, userWithStakedNft);
        vm.expectRevert(abi.encodeWithSelector(IZeroVp.ERC721NonexistentToken.selector, _tokenIds[0]));
        ISdZeroDepositor(address(depositor)).deposit(_tokenIds, true, userWithStakedNft);
    }

    function test_canJoinSdWithOldZeroLendLockAndNotStake() public {
        vm.startPrank(userWithStakedNft);

        // make sure the user doesn't have unstaked tokens
        assertEq(IZeroLocker(zeroLockerToken).balanceOf(userWithStakedNft), 0);

        (uint256[] memory _tokenIds, uint256 totalUserLockedAmount,) = _getLockedDetails(userWithStakedNft);
        (, uint256 totalSdLockedAmount,) = _getLockedDetails(locker);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IZeroVp(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // userWithStakedNft should have 0 sdToken before joining
        assertEq(IERC20(sdToken).balanceOf(userWithStakedNft), 0);

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        ISdZeroDepositor(address(depositor)).deposit(_tokenIds, false, userWithStakedNft);

        // ## test everything

        // locked amount of user was transfered to stake dao
        (, uint256 afterTotalSdLockedAmount, uint256 afterTotalSdPower) = _getLockedDetails(locker);
        assertEq(afterTotalSdLockedAmount, totalUserLockedAmount + totalSdLockedAmount);

        // since the user had an end date lower than 4 years and we rebased it
        // with the locker token when merging, we should have a larger total power
        (uint256 _start, uint256 _end) = _getLockerStartEndTime(locker);
        uint256 _diff = _end - _start;
        uint256 expectedNewPower = _diff * (totalSdLockedAmount + totalUserLockedAmount) / (4 * 365 * 24 * 3600);
        assertEq(afterTotalSdPower, expectedNewPower);

        // user doens't own any NFT and has no locks
        assertEq(IZeroLocker(zeroLockerToken).balanceOf(userWithStakedNft), 0);
        (uint256[] memory _afterTokenIds,) = IZeroVp(address(veZero)).getLockedNftDetails(userWithStakedNft);
        assertEq(_afterTokenIds.length, 0);

        assertEq(IERC20(sdToken).balanceOf(userWithStakedNft) > 0, true);
        assertEq(liquidityGauge.balanceOf(userWithStakedNft), 0);
    }

    function _appendNthTokenId(uint256[] memory _tokenIds, uint256 n) internal pure returns (uint256[] memory) {
        // Create a new memory array with length _tokenIds.length + 1
        uint256[] memory extendedArray = new uint256[](_tokenIds.length + 1);

        // Copy all elements from _tokenIds to extendedArray
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            extendedArray[i] = _tokenIds[i];
        }

        // Append the first element of _tokenIds to the end of the new array
        extendedArray[_tokenIds.length] = _tokenIds[n];

        return extendedArray;
    }

    function test_cantJoinSdForZeroAddress() public {
        vm.startPrank(userWithStakedNft);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IZeroVp(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        vm.expectRevert(abi.encodeWithSelector(IDepositor.ADDRESS_ZERO.selector));
        ISdZeroDepositor(address(depositor)).deposit(_appendNthTokenId(_tokenIds, 1), true, address(0));
    }

    function test_cantJoinSdWithDuplicateTokenIds() public {
        vm.startPrank(userWithStakedNft);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IZeroVp(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        vm.expectRevert(abi.encodeWithSelector(IZeroVp.ERC721NonexistentToken.selector, _tokenIds[1]));
        ISdZeroDepositor(address(depositor)).deposit(_appendNthTokenId(_tokenIds, 1), true, userWithStakedNft);
    }

    function test_cantForceSomeoneToJoin() public {
        vm.startPrank(userWithStakedNft);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IZeroVp(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(ISdZeroLocker.NotOwnerOfToken.selector, _tokenIds[0]));
        ISdZeroDepositor(address(depositor)).deposit(_tokenIds, true, userWithStakedNft);
    }

    function test_cantDepositDirectlyToLocker() public {
        vm.startPrank(userWithStakedNft);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IZeroVp(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        vm.expectRevert(ISdLocker.GOVERNANCE_OR_DEPOSITOR.selector);
        ISdZeroLocker(locker).deposit(userWithStakedNft, _tokenIds);
    }

    function test_emptyTokenIdsList() public {
        vm.startPrank(userWithStakedNft);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IZeroVp(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        uint256[] memory _emptyTokenIdsList;

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        vm.expectRevert(ISdZeroLocker.EmptyTokenIdList.selector);
        ISdZeroDepositor(address(depositor)).deposit(_emptyTokenIdsList, true, userWithStakedNft);
    }

    function test_canPartiallyDepositTokenIds() public {
        vm.startPrank(userWithStakedNft);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IZeroVp(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        uint256[] memory _shorterTokenIdsList = new uint256[](_tokenIds.length - 1);

        for (uint256 index = 0; index < _tokenIds.length - 1; index++) {
            _shorterTokenIdsList[index] = _tokenIds[index];
        }

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        ISdZeroDepositor(address(depositor)).deposit(_shorterTokenIdsList, true, userWithStakedNft);

        // user doens't own any NFT and has no locks
        assertEq(IZeroLocker(zeroLockerToken).balanceOf(userWithStakedNft), 1);
        (uint256[] memory _afterTokenIds,) = IZeroVp(address(veZero)).getLockedNftDetails(userWithStakedNft);
        assertEq(_afterTokenIds.length, 0);

        assertEq(IERC20(sdToken).balanceOf(userWithStakedNft), 0);
        assertEq(liquidityGauge.balanceOf(userWithStakedNft) > 0, true);
    }
}
