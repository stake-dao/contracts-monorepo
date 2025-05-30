// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {CurveLocker} from "address-book/src/CurveEthereum.sol";
import {DAO} from "address-book/src/DaoEthereum.sol";
import {DeployAccumulator} from "script/common/DeployAccumulator.sol";
import {CurveAccumulator} from "src/integrations/curve/Accumulator.sol";

contract Deploy is DeployAccumulator {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.TREASURY, DAO.LIQUIDITY_FEES_RECIPIENT, DAO.GOVERNANCE);
    }

    function _deployAccumulator() internal override returns (address payable) {
        return payable(
            new CurveAccumulator(address(CurveLocker.GAUGE), CurveLocker.LOCKER, msg.sender, CurveLocker.LOCKER)
        );
    }

    function _afterDeploy() internal virtual override {}

    function _beforeDeploy() internal virtual override {}
}
