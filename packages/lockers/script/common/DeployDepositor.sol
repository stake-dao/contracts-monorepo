// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "src/common/depositor/BaseDepositor.sol";

abstract contract DeployDepositor is Script {
    address internal depositor;

    function _run(address deployer, address governance) internal {
        vm.startBroadcast(deployer);

        depositor = _deployDepositor();

        _afterDeploy();

        BaseDepositor(depositor).transferGovernance(governance);

        vm.stopBroadcast();
    }

    function _deployDepositor() internal virtual returns (address);

    function _afterDeploy() internal virtual;
}
