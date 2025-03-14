// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "test/integration/curve/BaseCurveTest.t.sol";

contract CurveFactoryTest is BaseCurveTest {
    /// Random PID for testing.
    uint256 public constant PID = 421;

    constructor() BaseCurveTest(PID) {}

    function test_RevertWhenGaugeIsShutdownOnOldStrategy() public whenGaugeIsNotShutdownOnOldStrategy {
        /// 1. Revert by creating a single vault.
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidDeployment.selector));
        curveFactory.createVault(address(gauge));

        /// 2. Revert by creating using pid.
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidDeployment.selector));
        curveFactory.create(pid);
    }

    function test_DeployVaultWithoutConvexSidecar() public {}
}
