pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Accountant} from "src/Accountant.sol";

// Exposes the useful internal functions of the Accountant contract for testing purposes
contract AccountantHarness is Accountant, Test {
    constructor(address _owner, address _registry, address _rewardToken, bytes4 _protocolId)
        Accountant(_owner, _registry, _rewardToken, _protocolId)
    {}

    function exposed_defaultProtocolFee() external pure returns (uint256) {
        return DEFAULT_PROTOCOL_FEE;
    }

    function exposed_defaultHarvestFee() external pure returns (uint256) {
        return DEFAULT_HARVEST_FEE;
    }
}
