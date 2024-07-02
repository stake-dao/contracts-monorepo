// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";

import "script/base/Accumulator.s.sol";
import "src/frax/fxs/accumulator/FXSAccumulatorV3.sol";

contract Deploy is Accumulator {
    function _deployAccumulator() internal override returns (address payable) {
        return payable(new FXSAccumulatorV3(address(FXS.GAUGE), FXS.LOCKER, DAO.MAIN_DEPLOYER));
    }

    function _afterDeploy() internal virtual override {}
}
