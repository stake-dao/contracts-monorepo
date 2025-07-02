// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AutocompoundedVault} from "src/AutocompoundedVault.sol";
import {AutocompoundedVaultTest} from "test/unit/AutocompoundedVault/utils/AutocompoundedVaultTest.t.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract AutocompoundedVault__setRewards is AutocompoundedVaultTest {
    function test_RevertsWhenCalledByUnauthorizedAddress(address caller, uint256 amount) external {
        // it reverts when called by unauthorized address

        vm.assume(caller != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        autocompoundedVault.setRewards(amount);
    }

    function test_RevertsWhenCallerDoesntHaveEnoughBalance(uint256 balance) external {
        // it reverts when no ERC20 allowance

        balance = bound(balance, 1, 1e30);

        deal(autocompoundedVault.asset(), owner, balance);

        vm.expectRevert();
        vm.prank(owner);
        autocompoundedVault.setRewards(balance + 1);
    }

    function test_CreatesANewStreamWithGivenAmount(uint256 _amount) public {
        // it creates a new stream with given amount
        _amount = bound(_amount, 1, 1e30);

        address asset = autocompoundedVault.asset();

        // 1. Deal the asset to the owner
        deal(asset, owner, _amount);

        // 2. Approve the asset to the autocompounded vault
        vm.prank(owner);
        IERC20(asset).approve(address(autocompoundedVault), _amount);

        // 3. Set the rewards
        vm.prank(owner);
        autocompoundedVault.setRewards(_amount);

        // 4. Get the current stream
        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime) =
            autocompoundedVault.getCurrentStream();

        // 5. Assert the stream
        assertEq(amount, _amount);
        assertEq(remainingToken, _amount);
        assertEq(start, uint128(block.timestamp));
        assertEq(end, uint128(block.timestamp + autocompoundedVault.STREAMING_PERIOD()));
        assertEq(remainingTime, uint128(autocompoundedVault.STREAMING_PERIOD()));

        // 6. Assert the balance of the vault and the owner
        assertEq(IERC20(autocompoundedVault.asset()).balanceOf(address(autocompoundedVault)), _amount);
        assertEq(IERC20(autocompoundedVault.asset()).balanceOf(owner), 0);
    }

    function test_CreatesANewStreamWithGivenAndUnvestedAmount(uint256 _amountStream1, uint256 _amountStream2)
        external
    {
        // it creates a new stream with given and unvested amount

        _amountStream1 = bound(_amountStream1, 1e12, 1e20);
        _amountStream2 = bound(_amountStream2, 1e12, 1e20);

        address asset = autocompoundedVault.asset();

        // 1. Deal the asset to the owner
        deal(asset, owner, _amountStream1 + _amountStream2);

        // 2. Approve the asset to the autocompounded vault
        vm.prank(owner);
        IERC20(asset).approve(address(autocompoundedVault), _amountStream1);

        // 3. Set the first rewards
        vm.prank(owner);
        autocompoundedVault.setRewards(_amountStream1);

        // 4. warp to half the streaming period
        (,,,, uint128 remainingTime1) = autocompoundedVault.getCurrentStream();
        vm.warp(block.timestamp + remainingTime1 / 2);

        // 5. Approve the asset to the autocompounded vault
        vm.prank(owner);
        IERC20(asset).approve(address(autocompoundedVault), _amountStream2);

        // 6. Set the second rewards
        vm.prank(owner);
        autocompoundedVault.setRewards(_amountStream2);

        // 7. Get the current stream
        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime2) =
            autocompoundedVault.getCurrentStream();

        // 8. Assert the stream
        assertEq(amount, _amountStream1 / 2 + _amountStream2);
        assertEq(remainingToken, _amountStream1 / 2 + _amountStream2);
        assertEq(start, uint128(block.timestamp));
        assertEq(end, uint128(block.timestamp + autocompoundedVault.STREAMING_PERIOD()));
        assertEq(remainingTime2, uint128(autocompoundedVault.STREAMING_PERIOD()));
    }

    function test_EmitAnEvent() external {
        // it emit an event

        address asset = autocompoundedVault.asset();
        uint256 amount = 1e28;

        // 1. Deal the asset to the owner
        deal(asset, owner, amount);

        // 2. Approve the asset to the autocompounded vault
        IERC20(asset).approve(address(autocompoundedVault), amount);

        vm.expectEmit(true, true, true, true);
        emit NewStreamRewards(
            owner, amount, uint128(block.timestamp), uint128(block.timestamp + autocompoundedVault.STREAMING_PERIOD())
        );

        // 3. Set the rewards
        vm.prank(owner);
        autocompoundedVault.setRewards(amount);
    }

    /// @notice Event emitted when a new stream is started
    event NewStreamRewards(address indexed caller, uint256 amount, uint128 start, uint128 end);
}
