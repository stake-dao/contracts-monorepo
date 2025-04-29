// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "forge-std/src/Script.sol";
import "script/common/DeployAccumulator.sol";
import {YearnAccumulator} from "src/mainnet/yearn/Accumulator.sol";

contract Deploy is DeployAccumulator {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.MAIN_DEPLOYER, DAO.TREASURY, DAO.LIQUIDITY_FEES_RECIPIENT, DAO.GOVERNANCE);
    }

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new YearnAccumulator(address(YFI.GAUGE), YFI.LOCKER, DAO.MAIN_DEPLOYER, YFI.LOCKER));
    }

    function _afterDeploy() internal virtual override {}

    function _beforeDeploy() internal virtual override {}
}
