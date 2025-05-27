// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {YieldnestAutocompoundedVault} from "src/integrations/yieldnest/YieldnestAutocompoundedVault.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";

contract DeployYieldnestVaultScript is Script {
    function run() public returns (YieldnestAutocompoundedVault yieldnestAutocompoundedVault) {
        vm.startBroadcast();

        // 1. Deploy the YieldnestAutocompoundedVault contract
        yieldnestAutocompoundedVault = new YieldnestAutocompoundedVault();

        // 2. Transfer the ownership to the DAO governance
        yieldnestAutocompoundedVault.transferOwnership(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
