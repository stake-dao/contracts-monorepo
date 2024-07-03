// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/56.sol";
import "address-book/src/lockers/56.sol";

import "script/base/DeployAccumulator.sol";
import "src/cake/accumulator/CAKEAccumulator.sol";

contract Deploy is DeployAccumulator {
    function run() public {
        vm.createSelectFork("bnb");
        _run(DAO.MAIN_DEPLOYER, DAO.GOVERNANCE, DAO.GOVERNANCE, DAO.GOVERNANCE);
    }

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new CAKEAccumulator(address(CAKE.GAUGE), CAKE.LOCKER, DAO.MAIN_DEPLOYER));
    }

    function _afterDeploy() internal virtual override {}
}
