pragma solidity 0.8.28;

import {Accountant} from "src/Accountant.sol";
import {AccountantBaseTest} from "test/AccountantBaseTest.t.sol";
import {stdStorage, StdStorage, StdUtils} from "forge-std/src/Test.sol";
// import "forge-std/src/StdUtils.sol";

contract Accountant__getCurrentHarvestFee is AccountantBaseTest {
    using stdStorage for StdStorage;

    // utility function to override the HARVEST_URGENCY_THRESHOLD storage slot by hand
    // (keep the test unitarian and avoid calling the flow to set it as expected by code)
    function _cheat_override_harvestUrgencyThreshold(uint256 value) private {
        stdstore.target(address(accountant)).sig("HARVEST_URGENCY_THRESHOLD()").checked_write(value);
    }

    function test_ReturnsTheHarvestFeePercentWhenTheThresholdIs0() external {
        // it returns the harvest fee percent when the threshold is 0

        // 0 is the default value of `HARVEST_URGENCY_THRESHOLD`
        assertEq(accountant.HARVEST_URGENCY_THRESHOLD(), 0);

        // verify the both variables share the same values
        (, uint128 currentHarvestFeePercent) = accountant.feesParams();
        assertEq(accountant.getCurrentHarvestFee(), currentHarvestFeePercent);
    }

    function test_Returns0WhenTheERC20BalanceIsHigherThanTheTreshold(uint256 harvestTreshold, uint256 balance)
        external
    {
        // it returns 0 when the ERC20 balance is higher than the treshold

        // ensure balance is higher or equal than the harvest treshold
        vm.assume(harvestTreshold != 0);
        vm.assume(balance >= harvestTreshold);

        // manually set a random value for `HARVEST_URGENCY_THRESHOLD`
        _cheat_override_harvestUrgencyThreshold(harvestTreshold);
        assertEq(accountant.HARVEST_URGENCY_THRESHOLD(), harvestTreshold);

        // manually set a fake balance of reward token to the accountant contract
        deal(address(rewardToken), address(accountant), balance, true);
        assertEq(rewardToken.balanceOf(address(accountant)), balance);

        // verify the returned value is 0
        assertEq(accountant.getCurrentHarvestFee(), 0);
    }

    function test_CalculatesTheCurrentHarvestFeeWhenTheERC20BalanceIsLowerThanTheTreshold(
        uint128 harvestTreshold,
        uint128 balance
    ) external {
        // it calculates the current harvest fee when the ERC20 balance is lower than the treshold

        // ensure balance is stricly **lower** than the harvest treshold
        vm.assume(harvestTreshold != 0);
        vm.assume(balance < harvestTreshold);

        // manually set a random value for `HARVEST_URGENCY_THRESHOLD`
        _cheat_override_harvestUrgencyThreshold(harvestTreshold);

        // manually set a fake balance of reward token to the accountant contract
        deal(address(rewardToken), address(accountant), balance, true);
        assertEq(rewardToken.balanceOf(address(accountant)), balance);

        // verify the returned value is 0
        assertGe(accountant.getCurrentHarvestFee(), 0);
    }

    function test_RevertWhenTheERC20ContractReverts() external {
        // it revert when the ERC20 contract is missing the balanceOf function

        // manually set a random value for `HARVEST_URGENCY_THRESHOLD`
        _cheat_override_harvestUrgencyThreshold(5);

        // manually set a fake balance of reward token to the accountant contract
        vm.mockCallRevert(
            address(rewardToken),
            abi.encodeWithSelector(rewardToken.balanceOf.selector, address(accountant)),
            "REVERT_SD_MESSAGE"
        );

        vm.expectRevert("REVERT_SD_MESSAGE");
        accountant.getCurrentHarvestFee();
    }
}
