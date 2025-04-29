// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";
import "forge-std/src/Script.sol";
import "script/common/DeployDepositor.sol";
import {PendleDepositor} from "src/mainnet/pendle/Depositor.sol";

contract Deploy is DeployDepositor {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.MAIN_DEPLOYER, DAO.GOVERNANCE);
    }

    function _deployDepositor() internal override returns (address) {
        return address(new PendleDepositor(Pendle.PENDLE, PENDLE.LOCKER, PENDLE.SDTOKEN, PENDLE.GAUGE, PENDLE.LOCKER));
    }

    function _afterDeploy() internal override {}
}
