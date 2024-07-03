// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";

import "script/base/DeployAccumulator.sol";
import "src/apwine/accumulator/APWAccumulatorV3.sol";

contract Deploy is DeployAccumulator {
    function run() public {
        vm.createSelectFork("mainnet");
        _run(DAO.MAIN_DEPLOYER, DAO.TREASURY, DAO.LIQUIDITY_FEES_RECIPIENT, DAO.GOVERNANCE);
    }

    function _deployAccumulator() internal override returns (address payable) {
        return payable(new APWAccumulatorV3(address(SPECTRA.GAUGE), SPECTRA.LOCKER, DAO.MAIN_DEPLOYER));
    }

    function _afterDeploy() internal virtual override {}
}
