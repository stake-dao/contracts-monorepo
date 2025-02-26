pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Accountant} from "src/Accountant.sol";

contract Accountant__packFeesIntoSlot is Test {
    AccountantHarness accountant;

    function setUp() external {
        accountant = new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"));
    }

    function test_PackTheProtocolFeeCorrectly(uint256 protocolFee) external view {
        // it pack the protocol fee correctly

        protocolFee = bound(protocolFee, 1, accountant.MAX_FEE_PERCENT());

        uint256 harvestFee = 123_456;
        uint256 feesSlot = accountant.exposed_packFeesIntoSlot(protocolFee, harvestFee);

        assertEq(accountant.exposed_getProtocolFeePercent(feesSlot), protocolFee);
    }

    function test_PackTheHarvestFeeCorrectly(uint256 harvestFee) external view {
        // it pack the harvest fee correctly

        harvestFee = bound(harvestFee, 1, accountant.MAX_FEE_PERCENT());

        uint256 protocolFee = 123_456;
        uint256 feesSlot = accountant.exposed_packFeesIntoSlot(protocolFee, harvestFee);

        assertEq(accountant.exposed_getHarvestFeePercent(feesSlot), harvestFee);
    }
}

// Exposes the useful internal functions of the Accountant contract for testing purposes
contract AccountantHarness is Accountant {
    constructor(address owner, address registry, address rewardToken) Accountant(owner, registry, rewardToken) {}

    function exposed_getProtocolFeePercent(uint256 feesSlot) external pure returns (uint256) {
        return _getProtocolFeePercent(feesSlot);
    }

    function exposed_getHarvestFeePercent(uint256 feesSlot) external pure returns (uint256) {
        return _getHarvestFeePercent(feesSlot);
    }

    function exposed_packFeesIntoSlot(uint256 _protocolFee, uint256 _harvestFee) external pure returns (uint256) {
        return _packFeesIntoSlot(_protocolFee, _harvestFee);
    }
}
