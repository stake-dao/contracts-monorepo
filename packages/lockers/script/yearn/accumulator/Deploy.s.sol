// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {DAO} from "address-book/src/DAOEthereum.sol";
import {YearnLocker} from "address-book/src/YearnEthereum.sol";
import {DeployAccumulator} from "script/common/DeployAccumulator.sol";
import {YearnAccumulator} from "src/mainnet/yearn/Accumulator.sol";

contract Deploy is DeployAccumulator {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.MAIN_DEPLOYER, DAO.TREASURY, DAO.LIQUIDITY_FEES_RECIPIENT, DAO.GOVERNANCE);
    }

    function _deployAccumulator() internal override returns (address payable) {
        return payable(
            new YearnAccumulator(address(YearnLocker.GAUGE), YearnLocker.LOCKER, DAO.MAIN_DEPLOYER, YearnLocker.LOCKER)
        );
    }

    function _afterDeploy() internal virtual override {}

    function _beforeDeploy() internal virtual override {}
}
