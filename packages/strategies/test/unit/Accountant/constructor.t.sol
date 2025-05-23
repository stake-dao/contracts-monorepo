// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Test} from "forge-std/src/Test.sol";
import {Accountant} from "src/Accountant.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__Constructor is Test {
    function test_RevertGiven_OwnerIs0() external {
        // it reverts

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Accountant(address(0), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
    }

    function test_GivenOwnerIsNot0(address owner) external {
        // it initializes the owner
        // it emits the OwnershipTransferred event

        // we ensure the fuzzed address is not the zero address
        vm.assume(owner != address(0));

        // we tell forge to expect the OwnershipTransferred event
        vm.expectEmit(true, true, true, true);
        emit Ownable.OwnershipTransferred(address(0), owner);

        // we deploy the accountant and assert the owner is the one we set
        Accountant accountant = new Accountant(owner, makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
        assertEq(accountant.owner(), owner);
    }

    function test_RevertGiven_ProtocolControllerIs0() external {
        // it should revert

        vm.expectRevert(abi.encodeWithSelector(Accountant.InvalidProtocolController.selector));
        new Accountant(makeAddr("owner"), address(0), makeAddr("rewardToken"), bytes4(hex"11"));
    }

    function test_GivenProtocolControllerIsNot0(address registry) external {
        // it initializes the protocol controller

        // we ensure the fuzzed address is not the zero address
        vm.assume(registry != address(0));

        Accountant accountant = new Accountant(makeAddr("owner"), registry, makeAddr("rewardToken"), bytes4(hex"11"));
        assertEq(address(accountant.PROTOCOL_CONTROLLER()), registry);
    }

    function test_RevertGiven_RewardTokenIs0() external {
        // it should revert

        vm.expectRevert(abi.encodeWithSelector(Accountant.InvalidRewardToken.selector));
        new Accountant(makeAddr("owner"), makeAddr("registry"), address(0), bytes4(hex"11"));
    }

    function test_GivenRewardTokenIsNot0(address rewardToken) external {
        // it initializes the reward token

        // we ensure the fuzzed address is not the zero address
        vm.assume(rewardToken != address(0));

        Accountant accountant = new Accountant(makeAddr("owner"), makeAddr("registry"), rewardToken, bytes4(hex"11"));
        assertEq(accountant.REWARD_TOKEN(), rewardToken);
    }

    function test_InitializesTheFeesParams() external {
        // it initializes the fees slot

        Accountant accountant =
            new Accountant(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
        assertNotEq(accountant.getProtocolFeePercent(), 0);
        assertNotEq(accountant.getHarvestFeePercent(), 0);
    }

    function test_SetsProtocolFeeToDefaultValue() external {
        // it sets the protocol fee to default value

        AccountantHarness accountant =
            new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
        assertEq(accountant.getProtocolFeePercent(), accountant.exposed_defaultProtocolFee());
    }

    function test_SetsHarvestFeeToDefaultValue() external {
        // it sets the harvest fee to default value

        AccountantHarness accountant =
            new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
        assertEq(accountant.getHarvestFeePercent(), accountant.exposed_defaultHarvestFee());
    }

    function test_EmitsTheProtocolFeePercentSetEvent() external {
        // it emits the ProtocolFeePercentSet event

        // dummy deployment to expose the default constant value
        vm.pauseGasMetering();
        AccountantHarness accountant =
            new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
        vm.resumeGasMetering();

        vm.expectEmit(true, true, true, true, 1);
        emit Accountant.ProtocolFeePercentSet(0, accountant.exposed_defaultProtocolFee());

        new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
    }

    function test_EmitsTheHarvestFeePercentSetEvent() external {
        // it emits the HarvestFeePercentSet event

        // dummy deployment to expose the default constant value
        vm.pauseGasMetering();
        AccountantHarness accountant =
            new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
        vm.resumeGasMetering();

        vm.expectEmit(true, true, true, true, 1);
        emit Accountant.HarvestFeePercentSet(0, accountant.exposed_defaultHarvestFee());

        new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11"));
    }
}
