pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Accountant} from "src/Accountant.sol";

// Exposes the useful internal functions of the Accountant contract for testing purposes
contract AccountantHarness is Accountant, Test {
    constructor() Accountant(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"), bytes4(hex"11")) {}

    function exposed_defaultProtocolFee() external pure returns (uint256) {
        return DEFAULT_PROTOCOL_FEE;
    }

    function exposed_defaultHarvestFee() external pure returns (uint256) {
        return DEFAULT_HARVEST_FEE;
    }

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
