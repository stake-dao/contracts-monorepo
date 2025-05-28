// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {DAO} from "address-book/src/DaoEthereum.sol";
import {PendleLocker} from "address-book/src/PendleEthereum.sol";
import {DeployAccumulator} from "script/common/DeployAccumulator.sol";
import {PendleAccumulator} from "src/mainnet/pendle/Accumulator.sol";

contract Deploy is DeployAccumulator {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.TREASURY, DAO.LIQUIDITY_FEES_RECIPIENT, DAO.GOVERNANCE);
    }

    function _deployAccumulator() internal override returns (address payable) {
        return payable(
            new PendleAccumulator(address(PendleLocker.GAUGE), PendleLocker.LOCKER, msg.sender, PendleLocker.LOCKER)
        );
    }

    function _afterDeploy() internal virtual override {
        PendleAccumulator(payable(accumulator)).setTransferVotersRewards(true);
        PendleAccumulator(payable(accumulator)).setVotesRewardRecipient(PendleLocker.VOTERS_REWARDS_RECIPIENT);
    }

    function _beforeDeploy() internal virtual override {}
}
