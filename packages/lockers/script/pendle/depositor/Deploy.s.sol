// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DaoEthereum.sol";
import {PendleLocker} from "address-book/src/PendleEthereum.sol";
import {DeployDepositor} from "script/common/DeployDepositor.sol";
import {PendleDepositor} from "src/mainnet/pendle/Depositor.sol";

contract Deploy is DeployDepositor {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.GOVERNANCE);
    }

    function _deployDepositor() internal override returns (address) {
        return address(
            new PendleDepositor(
                PendleLocker.TOKEN, PendleLocker.LOCKER, PendleLocker.SDTOKEN, PendleLocker.GAUGE, PendleLocker.LOCKER
            )
        );
    }

    function _afterDeploy() internal override {}
}
