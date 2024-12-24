// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {StrategyHarness} from "test/unit/Strategy/StrategyHarness.t.sol";
import {StrategyBaseTest} from "test/StrategyBaseTest.t.sol";

contract Strategy__constructor is StrategyBaseTest {
    function test_CorrectlySetsProtocolController() public {
        StrategyHarness newStrategy =
            new StrategyHarness(address(registry), protocolId, address(locker), address(gateway));

        assertEq(address(newStrategy.PROTOCOL_CONTROLLER()), address(registry));
    }

    function test_CorrectlySetsAccountant() public {
        StrategyHarness newStrategy =
            new StrategyHarness(address(registry), protocolId, address(locker), address(gateway));

        assertEq(address(newStrategy.ACCOUNTANT()), address(accountant));
    }

    function test_CorrectlySetsLocker() public {
        StrategyHarness newStrategy =
            new StrategyHarness(address(registry), protocolId, address(locker), address(gateway));

        assertEq(address(newStrategy.LOCKER()), address(locker));
    }

    function test_CorrectlySetsGateway() public {
        StrategyHarness newStrategy =
            new StrategyHarness(address(registry), protocolId, address(locker), address(gateway));

        assertEq(address(newStrategy.GATEWAY()), address(gateway));
    }

    function test_CorrectlySetsProtocolId() public {
        StrategyHarness newStrategy =
            new StrategyHarness(address(registry), protocolId, address(locker), address(gateway));

        assertEq(newStrategy.PROTOCOL_ID(), protocolId);
    }

    function test_SetsLockerToGatewayWhenLockerIsZero() public {
        StrategyHarness newStrategy = new StrategyHarness(address(registry), protocolId, address(0), address(gateway));

        assertEq(address(newStrategy.LOCKER()), address(gateway));
    }
}
