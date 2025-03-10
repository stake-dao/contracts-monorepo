pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {RewardVault} from "src/RewardVault.sol";

// Exposes the useful internal functions of the RewardVault contract for testing purposes
contract RewardVaultHarness is RewardVault, Test {
    constructor(bytes4 protocolId, address protocolController, address accountant)
        RewardVault(protocolId, protocolController, accountant)
    {}
}
