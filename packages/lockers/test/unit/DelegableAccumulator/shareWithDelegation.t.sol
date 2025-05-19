// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVeBoost} from "src/common/interfaces/IVeBoost.sol";
import {DelegableAccumulatorTest} from "test/unit/DelegableAccumulator/utils/DelegableAccumulatorTest.t.sol";

contract DelegableAccumulator__shareWithDelegation is DelegableAccumulatorTest {
    function setUp() public virtual override {
        super.setUp();

        // airdrop some tokens to the contract
        deal(address(token), address(delegableAccumulator), 1000e18);
    }

    function test_Returns0IfTheBalanceOfTheContractIs0() external {
        // it returns 0 if the balance of the contract is 0

        // set the balance of the contract to 0
        deal(address(token), address(delegableAccumulator), 0);

        assertEq(delegableAccumulator._expose_shareWithDelegation(), 0);
    }

    function test_Returns0IfTheVeBoostContractIs0() external {
        // it returns 0 if the veBoost contract is 0

        // set the veBoost contract to 0
        vm.prank(governance);
        delegableAccumulator.setVeBoost(address(0));

        assertEq(delegableAccumulator._expose_shareWithDelegation(), 0);
    }

    function test_Returns0IfTheVeBoostDelegationIs0() external {
        // it returns 0 if the veBoostDelegation is 0

        // set the veBoostDelegation to 0
        vm.prank(governance);
        delegableAccumulator.setVeBoostDelegation(address(0));

        assertEq(delegableAccumulator._expose_shareWithDelegation(), 0);
    }

    function test_Returns0IfTheReceivedBalanceIs0() external {
        // it returns 0 if the received balance is 0

        vm.mockCall(address(veBoost), abi.encodeWithSelector(IVeBoost.received_balance.selector, locker), abi.encode(0));

        assertEq(delegableAccumulator._expose_shareWithDelegation(), 0);
    }

    /// @dev the multiplier is initally set to 0 in the `DelegableAccumulatorTest` setup function
    function test_SendsTheDelegationSharesToTheVeBoostDelegation() public {
        // it sends the delegation shares to the veBoostDelegation

        uint256 amount = 1e21;
        uint256 boostReceived = 445e23;
        uint256 lockerVEToken = 118e24;
        uint256 denominator = delegableAccumulator.DENOMINATOR();

        // airdrop some tokens to the contract
        deal(address(token), address(delegableAccumulator), amount);

        // mock the veBoost contract to return a realistic amount of boost received
        // (value snapshotted from CRV locker on mainnet on 2025-05-08)
        vm.mockCall(
            address(veBoost),
            abi.encodeWithSelector(IVeBoost.received_balance.selector, locker),
            abi.encode(boostReceived)
        );

        // mock the veToken contract to return a realistic balance of veToken
        // (value snapshotted from CRV locker on mainnet on 2025-05-08)
        vm.mockCall(
            address(veToken), abi.encodeWithSelector(ERC20.balanceOf.selector, locker), abi.encode(lockerVEToken)
        );

        uint256 delegationShare = delegableAccumulator._expose_shareWithDelegation();

        uint256 expectedDelegationShare = amount * (boostReceived * denominator / lockerVEToken) / denominator;
        if (delegableAccumulator.multiplier() != 0) {
            expectedDelegationShare = expectedDelegationShare * delegableAccumulator.multiplier() / denominator;
        }

        assertEq(delegationShare, expectedDelegationShare);
        assertEq(token.balanceOf(address(delegableAccumulator)), amount - delegationShare);
        assertEq(token.balanceOf(address(veBoostDelegation)), expectedDelegationShare);
    }

    function test_SendTheDelegationSharesMultipliedByTheMultiplierIfTheMultiplierIsNot0() external {
        // it send the delegation shares multiplied by the multiplier if the multiplier is not 0

        // set the multiplier to 1.5e18
        vm.prank(governance);
        delegableAccumulator.setMultiplier(15e17);

        test_SendsTheDelegationSharesToTheVeBoostDelegation();
    }

    function test_EmitsAnEvent() external {
        // it emits an event
    }
}
