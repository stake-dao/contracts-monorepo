// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AutocompoundedVault} from "src/AutocompoundedVault.sol";
import {AutocompoundedVaultTest} from "test/unit/AutocompoundedVault/utils/AutocompoundedVaultTest.t.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract AutocompoundedVault__setRewards is AutocompoundedVaultTest {
    function test_RevertsWhenCalledByUnauthorizedAddress(address caller, uint256 amount) external {
        // it reverts when called by unauthorized address

        _cheat_mockAllowed(false);

        vm.expectRevert(abi.encodeWithSelector(AutocompoundedVault.NotAuthorized.selector));
        vm.prank(caller);
        autocompoundedVault.setRewards(amount);
    }

    function test_RevertsWhenCallerDoesntHaveEnoughBalance(address caller, uint256 balance) external {
        // it reverts when no ERC20 allowance

        balance = bound(balance, 1, 1e30);

        _cheat_mockAllowed(true);

        deal(autocompoundedVault.asset(), caller, balance);

        vm.expectRevert();
        vm.prank(caller);
        autocompoundedVault.setRewards(balance + 1);
    }

    function test_CreatesANewStreamWithGivenAmount(address _caller, uint256 _amount) public {
        // it creates a new stream with given amount
        _assumeUnlabeledAddress(_caller);
        vm.label(_caller, "caller");
        _amount = bound(_amount, 1, 1e30);

        address asset = autocompoundedVault.asset();

        // 1. Mock the protocol controller to allow the caller to set rewards
        _cheat_mockAllowed(true);

        // 2. Deal the asset to the caller
        deal(asset, _caller, _amount);

        // 3. Approve the asset to the autocompounded vault
        vm.prank(_caller);
        IERC20(asset).approve(address(autocompoundedVault), _amount);

        // 4. Set the rewards
        vm.prank(_caller);
        autocompoundedVault.setRewards(_amount);

        // 5. Get the current stream
        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime) =
            autocompoundedVault.getCurrentStream();

        // 6. Assert the stream
        assertEq(amount, _amount);
        assertEq(remainingToken, _amount);
        assertEq(start, uint128(block.timestamp));
        assertEq(end, uint128(block.timestamp + autocompoundedVault.STREAMING_PERIOD()));
        assertEq(remainingTime, uint128(autocompoundedVault.STREAMING_PERIOD()));

        // 7. Assert the balance of the vault and the caller
        assertEq(IERC20(autocompoundedVault.asset()).balanceOf(address(autocompoundedVault)), _amount);
        assertEq(IERC20(autocompoundedVault.asset()).balanceOf(_caller), 0);
    }

    function test_CreatesANewStreamWithGivenAndUnvestedAmount(
        address _caller,
        uint256 _amountStream1,
        uint256 _amountStream2
    ) external {
        // it creates a new stream with given and unvested amount

        _assumeUnlabeledAddress(_caller);
        vm.label(_caller, "caller");
        _amountStream1 = bound(_amountStream1, 1e12, 1e20);
        _amountStream2 = bound(_amountStream2, 1e12, 1e20);

        address asset = autocompoundedVault.asset();

        // 1. Mock the protocol controller to allow the caller to set rewards
        _cheat_mockAllowed(true);

        // 2. Deal the asset to the caller
        deal(asset, _caller, _amountStream1 + _amountStream2);

        // 3. Approve the asset to the autocompounded vault
        vm.prank(_caller);
        IERC20(asset).approve(address(autocompoundedVault), _amountStream1);

        // 4. Set the first rewards
        vm.prank(_caller);
        autocompoundedVault.setRewards(_amountStream1);

        // 5. warp to half the streaming period
        (,,,, uint128 remainingTime1) = autocompoundedVault.getCurrentStream();
        vm.warp(block.timestamp + remainingTime1 / 2);

        // 6. Approve the asset to the autocompounded vault
        vm.prank(_caller);
        IERC20(asset).approve(address(autocompoundedVault), _amountStream2);

        // 7. Set the second rewards
        vm.prank(_caller);
        autocompoundedVault.setRewards(_amountStream2);

        // 8. Get the current stream
        (uint256 amount, uint256 remainingToken, uint128 start, uint128 end, uint128 remainingTime2) =
            autocompoundedVault.getCurrentStream();

        // 9. Assert the stream
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

        // 1. Mock the protocol controller to allow the caller to set rewards
        _cheat_mockAllowed(true);

        // 2. Deal the asset to the caller
        deal(asset, address(this), amount);

        // 3. Approve the asset to the autocompounded vault
        IERC20(asset).approve(address(autocompoundedVault), amount);

        vm.expectEmit(true, true, true, true);
        emit NewStreamRewards(
            address(this),
            amount,
            uint128(block.timestamp),
            uint128(block.timestamp + autocompoundedVault.STREAMING_PERIOD())
        );

        // 4. Set the rewards
        autocompoundedVault.setRewards(amount);
    }

    /// @notice Event emitted when a new stream is started
    event NewStreamRewards(address indexed caller, uint256 amount, uint128 start, uint128 end);
}
