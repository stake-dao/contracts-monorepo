// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "src/common/accumulator/BaseAccumulator.sol";

abstract contract DeployAccumulator is Script {
    address payable internal accumulator;

    address[] feeSplitReceivers = new address[](2);
    uint256[] feeSplitFees = new uint256[](2);

    function _run(address deployer, address treasury, address liquidityFeeRecipient, address governance) internal {
        vm.startBroadcast(deployer);

        accumulator = _deployAccumulator();

        feeSplitReceivers[0] = address(treasury);
        feeSplitFees[0] = 500; // 5% to dao

        feeSplitReceivers[1] = address(liquidityFeeRecipient);
        feeSplitFees[1] = 1000; // 5% to liquidity

        BaseAccumulator(accumulator).setFeeSplit(feeSplitReceivers, feeSplitFees);

        _afterDeploy();

        BaseAccumulator(accumulator).transferGovernance(governance);

        vm.stopBroadcast();
    }

    function _deployAccumulator() internal virtual returns (address payable);

    function _afterDeploy() internal virtual;
}
