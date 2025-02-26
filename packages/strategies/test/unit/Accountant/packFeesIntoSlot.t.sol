pragma solidity 0.8.28;

import {BaseTest} from "test/Base.t.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.sol";

contract Accountant__packFeesIntoSlot is BaseTest {
    AccountantHarness accountantHarness;

    function setUp() public override {
        super.setUp();
        accountantHarness = new AccountantHarness();
    }

    function test_PackTheProtocolFeeCorrectly(uint256 protocolFee) external view {
        // it pack the protocol fee correctly

        protocolFee = bound(protocolFee, 1, accountantHarness.MAX_FEE_PERCENT());

        uint256 harvestFee = 123_456;
        uint256 feesSlot = accountantHarness.exposed_packFeesIntoSlot(protocolFee, harvestFee);

        assertEq(accountantHarness.exposed_getProtocolFeePercent(feesSlot), protocolFee);
    }

    function test_PackTheHarvestFeeCorrectly(uint256 harvestFee) external view {
        // it pack the harvest fee correctly

        harvestFee = bound(harvestFee, 1, accountantHarness.MAX_FEE_PERCENT());

        uint256 protocolFee = 123_456;
        uint256 feesSlot = accountantHarness.exposed_packFeesIntoSlot(protocolFee, harvestFee);

        assertEq(accountantHarness.exposed_getHarvestFeePercent(feesSlot), harvestFee);
    }
}
