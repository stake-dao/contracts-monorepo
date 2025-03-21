pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Accountant} from "src/Accountant.sol";
import {AccountantBaseTest} from "test/AccountantBaseTest.t.sol";

contract Accountant__setHarvestFeePercent is AccountantBaseTest {
    function test_StoreTheNewThreshold(uint256 newThreshold) external {
        // it store valid harvest fee percent value

        vm.assume(accountant.HARVEST_URGENCY_THRESHOLD() != newThreshold);

        accountant.setHarvestUrgencyThreshold(newThreshold);

        assertEq(accountant.HARVEST_URGENCY_THRESHOLD(), newThreshold);
    }

    function test_RevertIfCalledByNonOwner(address caller) external {
        // it revert if called by non owner

        // ensure the caller is not the owner of the accountant contract
        vm.assume(caller != address(this));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        accountant.setHarvestUrgencyThreshold(42);
    }

    function test_EmitTheUpdateEvent(uint256 newThreshold) external {
        // it emit the harves event

        vm.assume(accountant.HARVEST_URGENCY_THRESHOLD() != newThreshold);

        vm.expectEmit(true, true, true, true);
        emit Accountant.HarvestUrgencyThresholdSet(accountant.HARVEST_URGENCY_THRESHOLD(), newThreshold);
        accountant.setHarvestUrgencyThreshold(newThreshold);
    }
}
