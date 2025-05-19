// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DAOEthereum.sol";
import {FXNLocker} from "address-book/src/FXNEthereum.sol";
import {DeployAccumulator} from "script/common/DeployAccumulator.sol";
import {FXNAccumulator} from "src/mainnet/fx/Accumulator.sol";

contract Deploy is DeployAccumulator {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.TREASURY, DAO.LIQUIDITY_FEES_RECIPIENT, DAO.GOVERNANCE);
    }

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new FXNAccumulator(address(FXNLocker.GAUGE), FXNLocker.LOCKER, msg.sender));
    }

    function _afterDeploy() internal virtual override {}

    function _beforeDeploy() internal virtual override {}
}
