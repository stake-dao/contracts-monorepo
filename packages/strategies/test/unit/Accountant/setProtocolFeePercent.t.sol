pragma solidity 0.8.28;

import {BaseTest} from "test/Base.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Accountant} from "src/Accountant.sol";

contract Accountant__setProtocolFeePercent is BaseTest {
    function test_GivenProtocolFeeIs0() external {
        // it stores the new value

        vm.prank(owner);
        accountant.setProtocolFeePercent(0);

        assertEq(accountant.getProtocolFeePercent(), 0);
    }

    function test_GivenProtocolFeeIsInTheRange(uint128 newProtocolFee) external {
        // it stores the new value

        // ensure the fuzzed value is between 1 and the max acceptable value (max - harvest - 1)
        newProtocolFee = _boundValidProtocolFee(newProtocolFee);

        // we set the new protocol fee as the owner
        vm.prank(owner);
        accountant.setProtocolFeePercent(newProtocolFee);

        assertEq(accountant.getProtocolFeePercent(), newProtocolFee);
    }

    function test_GivenProtocolFeeIsOutTheRange(uint128 newProtocolFee) external {
        // it reverts

        // ensure the fuzzed value is out the range
        newProtocolFee = uint128(
            bound(
                newProtocolFee, accountant.MAX_FEE_PERCENT() - accountant.getHarvestFeePercent() + 1, type(uint128).max
            )
        );

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Accountant.FeeExceedsMaximum.selector));
        accountant.setProtocolFeePercent(newProtocolFee);
    }

    function test_GivenProtocolFeeIsHigherThanMax(uint128 newProtocolFee) external {
        // it reverts

        newProtocolFee = uint128(bound(newProtocolFee, accountant.MAX_FEE_PERCENT() + 1, type(uint128).max));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Accountant.FeeExceedsMaximum.selector));
        accountant.setProtocolFeePercent(newProtocolFee);
    }

    function test_GivenProtocolFeeIsEqualToTheOldValue() external {
        // it stores the new value (even if it's the same)

        uint128 currentFee = accountant.getProtocolFeePercent();

        vm.prank(owner);
        accountant.setProtocolFeePercent(currentFee);

        assertEq(accountant.getProtocolFeePercent(), currentFee);
    }

    function test_NeverUpdatesTheHarvestFee(uint128 newProtocolFee) external {
        // it never updates the harvest fee

        // ensure the fuzzed value is in the valid range
        newProtocolFee = _boundValidProtocolFee(newProtocolFee);

        uint128 harvestFeeBefore = accountant.getHarvestFeePercent();

        vm.prank(owner);
        accountant.setProtocolFeePercent(newProtocolFee);

        // assert that the harvest fee has not been updated
        uint128 harvestFeeAfter = accountant.getHarvestFeePercent();
        assertEq(harvestFeeBefore, harvestFeeAfter);
    }

    function test_WhenItEmitsTheEvent(uint128 newProtocolFee) external {
        // it emits the new protocol fee
        // it emits the old protocol fee

        uint128 oldProtocolFee = accountant.getProtocolFeePercent();
        newProtocolFee = _boundValidProtocolFee(newProtocolFee);

        vm.expectEmit(true, true, true, true);
        emit Accountant.ProtocolFeePercentSet(oldProtocolFee, newProtocolFee);

        vm.prank(owner);
        accountant.setProtocolFeePercent(newProtocolFee);
    }

    function test_GivenCallerIsNotOwner(address notOwner) external {
        // it reverts

        vm.assume(notOwner != owner);

        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        accountant.setProtocolFeePercent(0.1e18);
    }

    function test_GivenCallerIsOwner(uint128 newProtocolFee) external {
        // it never reverts (when parameters are valid)

        uint128 validFee = _boundValidProtocolFee(newProtocolFee);

        vm.prank(owner);
        accountant.setProtocolFeePercent(validFee);

        assertEq(accountant.getProtocolFeePercent(), validFee);
    }
}
