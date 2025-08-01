// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {DAO} from "@address-book/src/DaoEthereum.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SYASDPENDLE} from "src/integrations/pendle/SYASDPENDLE.sol";
import {BoringOwnableUpgradeable} from "@pendle/v2-sy/libraries/BoringOwnableUpgradeable.sol";
import {IStandardizedYield} from "@pendle/v2-sy/../interfaces/IStandardizedYield.sol";

contract DeploySYasdPENDLE is Script {
    function run() public returns (IStandardizedYield deployment) {
        vm.createSelectFork("mainnet");

        vm.startBroadcast();
        address implementation = address(new SYASDPENDLE());

        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("initialize(string,string)")),
            "", // name - unused
            "" // symbol - unused
        );
        deployment = IStandardizedYield(address(new TransparentUpgradeableProxy(implementation, DAO.GOVERNANCE, data)));

        BoringOwnableUpgradeable(address(deployment)).transferOwnership(DAO.GOVERNANCE, true, false);
        vm.stopBroadcast();
    }
}
