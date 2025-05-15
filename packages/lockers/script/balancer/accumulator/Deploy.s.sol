// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {DAO} from "address-book/src/DAOEthereum.sol";
import {BalancerLocker} from "address-book/src/BalancerEthereum.sol";
import {DeployAccumulator} from "script/common/DeployAccumulator.sol";
import {BalancerAccumulator} from "src/mainnet/balancer/Accumulator.sol";

contract Deploy is DeployAccumulator {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.MAIN_DEPLOYER, DAO.TREASURY, DAO.LIQUIDITY_FEES_RECIPIENT, DAO.GOVERNANCE);
    }

    function _deployAccumulator() internal override returns (address payable) {
        return payable(
            new BalancerAccumulator(
                address(BalancerLocker.GAUGE), BalancerLocker.LOCKER, DAO.MAIN_DEPLOYER, BalancerLocker.LOCKER
            )
        );
    }

    function _afterDeploy() internal virtual override {}

    function _beforeDeploy() internal virtual override {}
}
