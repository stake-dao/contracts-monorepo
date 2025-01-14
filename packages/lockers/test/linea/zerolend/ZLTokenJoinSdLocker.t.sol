// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import {BaseZeroLendTokenTest} from "test/linea/zerolend/common/BaseZeroLendTokenTest.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import {IOmnichainStakingBase} from "src/common/interfaces/zerolend/omnichainstaking/IOmnichainStakingBase.sol";
import {ILocker as IOmnichainLocker} from "src/common/interfaces/zerolend/omnichainstaking/ILocker.sol";
import {ISdZeroLocker} from "src/common/interfaces/zerolend/ISdZeroLocker.sol";
import {ISdZeroDepositor} from "src/common/interfaces/zerolend/ISdZeroDepositor.sol";
import {IZeroLocker} from "src/common/interfaces/zerolend/IZeroLocker.sol";

// end to end tests for the ZeroLend integration
contract ZeroLendTest is BaseZeroLendTokenTest {
    constructor() {}

    address userWithStakedNft = 0xB50C52FA0f34587063563321dc1c28Bc98bd8237;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("linea"), 14_369_758);
        vm.selectFork(forkId);

        _deployZeroIntegration();
    }

    function _getLockedDetails(address _user)
        internal
        view
        returns (uint256[] memory _tokenIds, uint256 _amount, uint256 _power)
    {
        (uint256[] memory tempTokenIds, IOmnichainLocker.LockedBalance[] memory _lockedBalances) =
            IOmnichainStakingBase(address(veZero)).getLockedNftDetails(_user);

        _tokenIds = tempTokenIds;

        for (uint256 index = 0; index < _lockedBalances.length; index++) {
            _amount += _lockedBalances[index].amount;
            _power += _lockedBalances[index].power;
        }
    }

    function test_canJoinSdWithOldZeroLendLock() public {
        vm.startPrank(userWithStakedNft);

        // make sure the user doesn't have unstaked tokens
        assertEq(IZeroLocker(zeroLockerToken).balanceOf(userWithStakedNft), 0);

        (uint256[] memory _tokenIds, uint256 totalUserLockedAmount, uint256 totalUserPower) =
            _getLockedDetails(userWithStakedNft);
        (, uint256 totalSdLockedAmount, uint256 totalSdPower) = _getLockedDetails(locker);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IOmnichainStakingBase(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        ISdZeroDepositor(address(depositor)).deposit(_tokenIds, true, address(this));

        // ## test everything

        // locked amount of user was transfered to stake dao
        (, uint256 afterTotalSdLockedAmount, uint256 afterTotalSdPower) = _getLockedDetails(locker);
        assertEq(afterTotalSdLockedAmount, totalUserLockedAmount + totalSdLockedAmount);

        // since the user had an end date lower than 4 years and we rebased it
        // with the locker token when merging, we should have a larger total power
        // TODO check the math to make sure it checks
        assertEq(afterTotalSdPower >= totalSdPower + totalUserPower, true);

        // user doens't own any NFT and has no locks
        assertEq(IZeroLocker(zeroLockerToken).balanceOf(userWithStakedNft), 0);
        (uint256[] memory _afterTokenIds,) =
            IOmnichainStakingBase(address(veZero)).getLockedNftDetails(userWithStakedNft);
        assertEq(_afterTokenIds.length, 0);

        // TODO test that userWithStakedNft got sdZERO tokens
    }

    // TODO more tests

    function test_cantJoinSdMultipleTimes() public {
        vm.startPrank(userWithStakedNft);

        // make sure the user doesn't have unstaked tokens
        assertEq(IZeroLocker(zeroLockerToken).balanceOf(userWithStakedNft), 0);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IOmnichainStakingBase(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        ISdZeroDepositor(address(depositor)).deposit(_tokenIds, true, userWithStakedNft);
        vm.expectRevert(abi.encodeWithSelector(IOmnichainStakingBase.ERC721NonexistentToken.selector, _tokenIds[0]));
        ISdZeroDepositor(address(depositor)).deposit(_tokenIds, true, userWithStakedNft);
    }

    // TODO test without staking

    // TODO test with different _user than msg.sender

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

    function test_cantJoinSdWithDuplicateTokenIds() public {
        vm.startPrank(userWithStakedNft);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IOmnichainStakingBase(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);
        vm.expectRevert(abi.encodeWithSelector(IOmnichainStakingBase.ERC721NonexistentToken.selector, _tokenIds[1]));
        ISdZeroDepositor(address(depositor)).deposit(_appendNthTokenId(_tokenIds, 1), true, userWithStakedNft);
    }

    function test_cantForceSomeoneToJoin() public {
        vm.startPrank(userWithStakedNft);

        (uint256[] memory _tokenIds,,) = _getLockedDetails(userWithStakedNft);

        for (uint256 index = 0; index < _tokenIds.length; index++) {
            IOmnichainStakingBase(address(veZero)).unstakeToken(_tokenIds[index]);
        }

        // ## join StakeDAO
        IZeroLocker(zeroLockerToken).setApprovalForAll(locker, true);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(ISdZeroLocker.NotOwnerOfToken.selector, _tokenIds[0]));
        ISdZeroDepositor(address(depositor)).deposit(_tokenIds, true, userWithStakedNft);
    }

    // can't call deposit on the locker directly

    // test call deposit with empty _tokenIds list

    // canPartiallyJoin
}
