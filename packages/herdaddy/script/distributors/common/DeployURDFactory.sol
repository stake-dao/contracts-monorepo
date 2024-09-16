// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Script.sol";
import "src/distributors/UrdFactory.sol";

abstract contract DeployURDFactory is Script {
    address payable internal urdFactory;

    function _run(address deployer) internal {
        vm.startBroadcast(deployer);

        urdFactory = _deployFactory();

        _afterDeploy();

        vm.stopBroadcast();
    }

    function _deployFactory() internal virtual returns (address payable);

    function _afterDeploy() internal virtual;
}
