// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DaoEthereum.sol";
import {DeployDepositor} from "script/common/DeployDepositor.sol";
import {YieldnestLocker, YieldnestProtocol} from "address-book/src/YieldnestEthereum.sol";
import {YieldnestDepositor} from "src/integrations/yieldnest/Depositor.sol";

contract Deploy is DeployDepositor {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.GOVERNANCE);
    }

    function _deployDepositor() internal override returns (address) {
        return address(
            new YieldnestDepositor(
                YieldnestProtocol.YND, YieldnestProtocol.LOCKER, YieldnestProtocol.SDYND, YieldnestProtocol.GAUGE, YieldnestProtocol.PRELAUNCH_LOCKER
            )
        );
    }

    function _afterDeploy() internal override {}
}
