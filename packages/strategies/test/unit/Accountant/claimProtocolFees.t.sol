// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "forge-std/src/interfaces/IERC20.sol";
import {stdStorage, StdStorage} from "forge-std/src/Test.sol";
import {Accountant} from "src/Accountant.sol";
import {AccountantBaseTest, MockRegistry, ERC20Mock} from "test/AccountantBaseTest.t.sol";

contract Accountant__claimProtocolFees is AccountantBaseTest {
    using stdStorage for StdStorage;

    // utility function to override the protocolFeesAccrued storage slot by hand
    // (keep the test unitarian and avoid calling the flow to set it as expected by code)
    function _cheat_override_protocolFeesAccrued(uint256 newProtocolFeesAccrued) private {
        stdstore.target(address(accountant)).sig("protocolFeesAccrued()").checked_write(newProtocolFeesAccrued);
    }

    modifier _cheat_setup_protocolFeesAccrued(address feeReceiver, uint256 protocolFeesAccrued) {
        // ------------------------------------------------------------------------
        // ------------------------------ INIT ------------------------------------
        // ------------------------------------------------------------------------

        // make sure the feeReceiver is valid (not 0 and not the accountant itself)
        vm.assume(feeReceiver != address(0) && feeReceiver != address(accountant));
        // airdrop enough ERC20 tokens to be transferred from the accountant to the receiver
        deal(address(rewardToken), address(accountant), protocolFeesAccrued);
        // make sure the init balances are correct for the test
        assertEq(rewardToken.balanceOf(address(accountant)), protocolFeesAccrued);
        // override the protocolFeesAccrued to the amount to be transferred
        // this cheatcode modifies the value of the variable `protocolFeesAccrued`
        // in the storage slot of the contract
        _cheat_override_protocolFeesAccrued(protocolFeesAccrued);
        // mock the call to the registry.feeReceiver to return the expected receiver
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(MockRegistry.feeReceiver.selector, protocolId),
            abi.encode(feeReceiver)
        );

        // pass control to the test
        _;
    }

    function test_WhenFeeReceiverIs0() external {
        // it reverts

        // mock the call to the registry.feeReceiver to return the expected receiver
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(MockRegistry.feeReceiver.selector, protocolId),
            abi.encode(address(0))
        );

        // expect the accountant to revert with the NoFeeReceiver error
        vm.expectRevert(abi.encodeWithSelector(Accountant.NoFeeReceiver.selector));
        accountant.claimProtocolFees();
    }

    function test_WhenFeeReceiverIsCorrect(address feeReceiver, uint256 protocolFeesAccrued)
        external
        _cheat_setup_protocolFeesAccrued(feeReceiver, protocolFeesAccrued)
    {
        uint256 feeReceiverBalanceBefore = rewardToken.balanceOf(feeReceiver);

        // claim the protocol fees
        accountant.claimProtocolFees();

        // make sure the transfer of reward tokens (accountant -> feeReceiver) has been made
        assertEq(rewardToken.balanceOf(address(accountant)), 0);
        assertEq(rewardToken.balanceOf(feeReceiver), feeReceiverBalanceBefore + protocolFeesAccrued);
    }

    function test_IsSafeFromReentrancy() external {
        // it is safe from reentrancy

        address maliciousERC20 = address(new ERC20MockMaliciousReeantrancy("Malicious ERC20", "MAL", 18));

        // mock the future call to the registry to return a valid fee receiver
        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(MockRegistry.feeReceiver.selector, protocolId),
            abi.encode(makeAddr("receiver"))
        );

        // Next time the transfer() method of the rewardToken is called
        // - It will call the transfer() method of the maliciousERC20 instead
        // - The maliciousERC20 will call the accountant.claimProtocolFees() function again in the same tx
        // - The accountant.claimProtocolFees() function MUST revert to ensure we are safe from reentrancy
        vm.mockFunction(address(rewardToken), address(maliciousERC20), abi.encodeWithSelector(IERC20.transfer.selector));

        // expect the accountant to revert with the ReentrancyGuardReentrantCall error
        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector));

        // try to claim the protocol fees
        accountant.claimProtocolFees();
    }

    function test_ResetsProtocolFeesAccruedTo0(address feeReceiver, uint256 protocolFeesAccrued)
        external
        _cheat_setup_protocolFeesAccrued(feeReceiver, protocolFeesAccrued)
    {
        // it resets protocolFeesAccrued to 0

        // make sure the fuzzed value for the protocolFeesAccrued is not 0
        vm.assume(protocolFeesAccrued != 0);

        uint256 protocolFeesAccruedBefore = accountant.protocolFeesAccrued();
        assertNotEq(protocolFeesAccruedBefore, 0);

        // claim the protocol fees
        accountant.claimProtocolFees();

        // make sure the protocolFeesAccrued has been reset to 0
        assertEq(accountant.protocolFeesAccrued(), 0);
    }

    function test_CanBeCalledByAnyAddress(address caller) external {
        // it can be called by any address

        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(MockRegistry.feeReceiver.selector, protocolId),
            abi.encode(makeAddr("receiver"))
        );

        vm.prank(caller);
        accountant.claimProtocolFees();
    }

    function test_EmitsTheProtocolFeesClaimedEvent(address feeReceiver, uint256 protocolFeesAccrued)
        external
        _cheat_setup_protocolFeesAccrued(feeReceiver, protocolFeesAccrued)
    {
        // it emits the ProtocolFeesClaimed event

        vm.expectEmit(true, true, true, true, address(accountant));
        emit Accountant.ProtocolFeesClaimed(protocolFeesAccrued);

        // claim the protocol fees
        accountant.claimProtocolFees();
    }

    function test_EmitsTheTransferEvent(address feeReceiver, uint256 protocolFeesAccrued)
        external
        _cheat_setup_protocolFeesAccrued(feeReceiver, protocolFeesAccrued)
    {
        // it emits the Transfer event

        vm.expectEmit(true, true, true, true, address(rewardToken));
        emit IERC20.Transfer(address(accountant), feeReceiver, protocolFeesAccrued);

        // claim the protocol fees
        accountant.claimProtocolFees();
    }

    function test_RevertsWhenTheRegistryReverts() external {
        // it reverts when the registry reverts

        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(MockRegistry.feeReceiver.selector, protocolId),
            abi.encode(address(1))
        );

        // mock the call to the rewardToken.transfer and force it to revert
        vm.mockCallRevert(
            address(registry),
            abi.encodeWithSelector(MockRegistry.feeReceiver.selector, protocolId),
            "UNCONTROLLED_SD_ERROR"
        );

        // expect the accountant to revert with the exact same error as the one mocked
        vm.expectRevert("UNCONTROLLED_SD_ERROR", address(registry), 1);
        accountant.claimProtocolFees();
    }

    function test_RevertsWhenERC20Reverts() external {
        // it reverts when ERC20 reverts

        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(MockRegistry.feeReceiver.selector, protocolId),
            abi.encode(address(1))
        );

        // mock the call to the rewardToken.transfer and force it to revert
        vm.mockCallRevert(
            address(rewardToken),
            abi.encodeWithSelector(IERC20.transfer.selector, address(1)),
            "UNCONTROLLED_EXTERNAL_ERROR"
        );

        // expect the accountant to revert with the exact same error as the one mocked
        vm.expectRevert("UNCONTROLLED_EXTERNAL_ERROR", address(rewardToken), 1);
        accountant.claimProtocolFees();
    }
}

contract ERC20MockMaliciousReeantrancy is ERC20Mock {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20Mock(name, symbol, decimals) {}

    // this is a malicious transfer() function that will recall accountant.claimProtocolFees()
    function transfer(address, uint256) public override returns (bool) {
        Accountant(msg.sender).claimProtocolFees();
        // expected to never reach this point because the call above MUST revert
        return true;
    }
}
