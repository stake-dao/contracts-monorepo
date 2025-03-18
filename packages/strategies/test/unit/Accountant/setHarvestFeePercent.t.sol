pragma solidity 0.8.28;

import {AccountantBaseTest} from "test/AccountantBaseTest.t.sol";
import {Accountant} from "src/Accountant.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract Accountant__setHarvestFeePercent is AccountantBaseTest {
    function test_RevertWhenTotalFeeExceedTheMaxFeePercent(uint128 newHarvestFeePercent) external {
        // it revert when total fee exceed the max fee percent

        (uint128 currentProtocolFeePercent,) = accountant.feesParams();
        vm.assume(
            (uint256(newHarvestFeePercent) + uint256(currentProtocolFeePercent)) > uint256(accountant.MAX_FEE_PERCENT())
        );

        vm.expectRevert(Accountant.FeeExceedsMaximum.selector);
        accountant.setHarvestFeePercent(newHarvestFeePercent);
    }

    function test_StoreValidHarvestFeePercentValue(uint128 newHarvestFeePercent) external {
        // it store valid harvest fee percent value

        (uint128 currentProtocolFeePercent, uint128 currentHarvestFeePercent) = accountant.feesParams();
        vm.assume(currentHarvestFeePercent != newHarvestFeePercent);
        vm.assume(
            (uint256(newHarvestFeePercent) + uint256(currentProtocolFeePercent)) < uint256(accountant.MAX_FEE_PERCENT())
        );

        accountant.setHarvestFeePercent(newHarvestFeePercent);

        (, uint128 storedHarvestFeePercent) = accountant.feesParams();
        assertEq(newHarvestFeePercent, storedHarvestFeePercent);
    }

    function test_RevertIfCalledByNonOwner(address caller) external {
        // it revert if called by non owner

        // ensure the caller is not the owner of the accountant contract
        vm.assume(caller != address(this));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        accountant.setHarvestFeePercent(42);
    }

    function test_EmitTheHarvestEvent(uint128 newHarvestFeePercent) external {
        // it emit the harves event

        (uint128 currentProtocolFeePercent, uint128 currentHarvestFeePercent) = accountant.feesParams();
        vm.assume(
            (uint256(newHarvestFeePercent) + uint256(currentProtocolFeePercent)) < uint256(accountant.MAX_FEE_PERCENT())
        );

        vm.expectEmit(true, true, true, true);
        emit Accountant.HarvestFeePercentSet(currentHarvestFeePercent, newHarvestFeePercent);
        accountant.setHarvestFeePercent(newHarvestFeePercent);
    }
}
