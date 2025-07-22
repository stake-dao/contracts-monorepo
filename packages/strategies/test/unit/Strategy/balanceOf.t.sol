// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {MockSidecar} from "test/mocks/MockSidecar.sol";
import {StrategyBaseTest} from "test/StrategyBaseTest.t.sol";

contract Strategy__balanceOf is StrategyBaseTest {
    function setUp() public override {
        super.setUp();

        // Mock the vault function of the IProtocolController interface
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IProtocolController.vault.selector, gauge),
            abi.encode(address(vault))
        );
    }

    function test_CorrectlyRetrievesBalanceFromLocker(uint256 lockerBalance) public {
        stakingToken.mint(address(locker), lockerBalance);

        address[] memory targets = new address[](1);
        targets[0] = address(locker);
        strategy._cheat_setAllocationTargets(gauge, address(allocator), targets);

        /// 1. It correctly retrieves the balance from the locker.
        /// 2. It correctly retrieve allocation targets.
        assertEq(strategy.balanceOf(gauge), lockerBalance);

        /// Mock the allocator to return an empty address.
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IProtocolController.allocator.selector, protocolId),
            abi.encode(address(0))
        );

        /// 3. It correctly retrieves the allocator.
        /// Thus reverting if wrong.
        vm.expectRevert();
        strategy.balanceOf(gauge);
    }

    function test_ReturnsTotalBalanceAcrossAllTargets() public {
        address[] memory targets = new address[](3);
        targets[0] = address(locker);
        targets[1] = address(new MockSidecar(gauge, address(rewardToken), accountant));
        targets[2] = address(new MockSidecar(gauge, address(rewardToken), accountant));

        stakingToken.mint(address(locker), 100);
        stakingToken.mint(targets[1], 200);
        stakingToken.mint(targets[2], 300);

        /// Mock the allocator to return the correct targets.
        strategy._cheat_setAllocationTargets(gauge, address(allocator), targets);

        /// 1. It correctly sums the balances from all targets.
        assertEq(strategy.balanceOf(gauge), 600);
    }
}
