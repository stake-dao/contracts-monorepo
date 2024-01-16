// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {FXNAccumulator} from "src/fx/accumulator/FXNAccumulator.sol";

contract DeployFXNAccumulator is Script {
    FXNAccumulator public accumulator;

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address gauge = 0xbcfE5c47129253C6B8a9A00565B3358b488D42E0;
    address locker = 0x75736518075a01034fa72D675D36a47e9B06B2Fb;
    address distributor = 0x8Dc551B4f5203b51b5366578F42060666D42AB5E;

    function run() public {
        vm.startBroadcast(DEPLOYER);

        accumulator = new FXNAccumulator(gauge, locker, GOVERNANCE, GOVERNANCE, DEPLOYER);

        accumulator.setDistributor(distributor);
        /// Set the dao fee to 15% and the liquidity fee to 0% to avoid many transfers since we don't have yet liquidity fee recipients.
        accumulator.setDaoFee(1500);
        accumulator.setLiquidityFee(0);
        accumulator.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();
    }
}
