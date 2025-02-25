pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Accountant} from "src/Accountant.sol";

// Contract that exposes the usful internal functions of the Accountant contract for testing purposes
contract AccountantHarness is Accountant {
    constructor(address owner, address registry, address rewardToken) Accountant(owner, registry, rewardToken) {}

    function exposed_calculateFeesSlot(uint256 protocolFee, uint256 harvestFee) external pure returns (uint256) {
        return _calculateFeesSlot(protocolFee, harvestFee);
    }

    function exposed_defaultProtocolFee() external pure returns (uint256) {
        return DEFAULT_PROTOCOL_FEE;
    }

    function exposed_defaultHarvestFee() external pure returns (uint256) {
        return DEFAULT_HARVEST_FEE;
    }
}

contract Accountant__Constructor is Test {
    function test_RevertWhen_TheOwnerIsTheZeroAddress() external {
        // it reverts

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Accountant(address(0), makeAddr("registry"), makeAddr("rewardToken"));
    }

    function test_WhenTheOwnerIsNotTheZeroAddress(address owner) external {
        // it initializes the owner
        // it emits the OwnershipTransferred event

        // we ensure the owner is not the zero address
        vm.assume(owner != address(0));

        // we tell forge to expect the OwnershipTransferred event
        vm.expectEmit(true, true, true, true);
        emit Ownable.OwnershipTransferred(address(0), owner);

        // we deploy the accountant and assert the owner is the one we set
        Accountant accountant = new Accountant(owner, makeAddr("registry"), makeAddr("rewardToken"));
        assertEq(accountant.owner(), owner);
    }

    function test_InitializesTheProtocolController(address registry) external {
        // it initializes the protocol controller

        Accountant accountant = new Accountant(makeAddr("owner"), registry, makeAddr("rewardToken"));
        assertEq(accountant.PROTOCOL_CONTROLLER(), registry);
    }

    function test_InitializesTheRewardToken(address rewardToken) external {
        // it initializes the reward token

        Accountant accountant = new Accountant(makeAddr("owner"), makeAddr("registry"), rewardToken);
        assertEq(accountant.REWARD_TOKEN(), rewardToken);
    }

    function test_InitializesTheFeesSlot() external {
        // it initializes the fees slot

        Accountant accountant = new Accountant(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"));
        assertNotEq(accountant.fees(), 0);
    }

    function test_SetsTheProtocolFeeToDefaultValue() external {
        // it sets the protocol fee to default value

        AccountantHarness accountant = new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"));
        assertEq(accountant.getProtocolFeePercent(), accountant.exposed_defaultProtocolFee());
    }

    function test_SetsTheHarvestFeeToDefaultValue() external {
        // it sets the harvest fee to default value

        AccountantHarness accountant = new AccountantHarness(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"));
        assertEq(accountant.getHarvestFeePercent(), accountant.exposed_defaultHarvestFee());
    }

    function test_PreservesTheHarvestUrgencyThresholdValue() external {
         // it preserves the harvest urgency threshold value

        Accountant accountant = new Accountant(makeAddr("owner"), makeAddr("registry"), makeAddr("rewardToken"));
        assertEq(accountant.HARVEST_URGENCY_THRESHOLD(), 0);
    }
}
