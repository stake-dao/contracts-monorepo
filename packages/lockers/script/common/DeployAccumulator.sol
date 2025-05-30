// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "forge-std/src/Script.sol";
import "src/AccumulatorBase.sol";

abstract contract DeployAccumulator is Script {
    address payable internal accumulator;

    function _run(address treasury, address liquidityFeeRecipient, address governance) internal {
        vm.startBroadcast();

        _beforeDeploy();

        accumulator = _deployAccumulator();

        AccumulatorBase.Split[] memory splits = new AccumulatorBase.Split[](2);
        splits[0] = AccumulatorBase.Split(address(treasury), 5e16);
        splits[1] = AccumulatorBase.Split(address(liquidityFeeRecipient), 10e16);

        AccumulatorBase(accumulator).setFeeSplit(splits);

        _afterDeploy();

        AccumulatorBase(accumulator).transferGovernance(governance);

        vm.stopBroadcast();
    }

    function _deployAccumulator() internal virtual returns (address payable);

    function _afterDeploy() internal virtual;

    function _beforeDeploy() internal virtual;
}
