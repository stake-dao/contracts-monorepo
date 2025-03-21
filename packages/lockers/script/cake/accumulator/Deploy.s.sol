// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "address-book/src/dao/56.sol";
import "address-book/src/lockers/56.sol";
import "forge-std/src/Script.sol";
import "script/common/DeployAccumulator.sol";
import "src/bnb/cake/Accumulator.sol";

contract Deploy is DeployAccumulator {
    function run() public {
        vm.createSelectFork("bnb");
        _run(DAO.MAIN_DEPLOYER, DAO.GOVERNANCE, DAO.GOVERNANCE, DAO.GOVERNANCE);
    }

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new Accumulator(address(CAKE.GAUGE), CAKE.LOCKER, DAO.MAIN_DEPLOYER));
    }

    function _afterDeploy() internal virtual override {}

    function _beforeDeploy() internal virtual override {}
}
