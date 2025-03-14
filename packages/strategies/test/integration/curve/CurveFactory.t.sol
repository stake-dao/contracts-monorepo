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

    function test_RevertWhenGaugeIsInvalid() public {
        address invalidGauge = makeAddr("Invalid Gauge");

        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidGauge.selector));
        curveFactory.createVault(invalidGauge);
    }

    function test_RevertWhenGaugeIsAlreadyDeployed() public {
        address nonNullAddress = makeAddr("Non Null Address");

        vm.mockCall(
            address(protocolController),
            abi.encodeWithSelector(IProtocolController.vaults.selector, gauge),
            abi.encode(nonNullAddress)
        );

        vm.expectRevert(abi.encodeWithSelector(Factory.AlreadyDeployed.selector));
        curveFactory.createVault(address(gauge));
    }

    function test_createVault() public {
        (address vault, address rewardReceiver) = curveFactory.createVault(address(gauge));

        RewardVault vaultContract = RewardVault(vault);
        RewardReceiver rewardReceiverContract = RewardReceiver(rewardReceiver);

        assertEq(vaultContract.gauge(), address(gauge));
        assertEq(vaultContract.asset(), address(lpToken));

        assertEq(address(rewardReceiverContract.rewardVault()), vault);
    }
    
}
