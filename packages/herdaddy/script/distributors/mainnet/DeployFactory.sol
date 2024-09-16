// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/1.sol";

import "src/distributors/UrdFactory.sol";
import "script/distributors/common/DeployURDFactory.sol";

contract Deploy is DeployURDFactory {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.MAIN_DEPLOYER);
    }

    function _deployFactory() internal override returns (address payable) {
        return payable(address(new UrdFactory()));
    }

    function _afterDeploy() internal virtual override {}
}
