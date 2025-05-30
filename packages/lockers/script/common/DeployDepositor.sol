// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "forge-std/src/Script.sol";
import "src/DepositorBase.sol";

abstract contract DeployDepositor is Script {
    address internal depositor;

    function _run(address governance) internal {
        vm.startBroadcast();

        depositor = _deployDepositor();

        _afterDeploy();

        DepositorBase(depositor).transferGovernance(governance);

        vm.stopBroadcast();
    }

    function _deployDepositor() internal virtual returns (address);

    function _afterDeploy() internal virtual;
}
