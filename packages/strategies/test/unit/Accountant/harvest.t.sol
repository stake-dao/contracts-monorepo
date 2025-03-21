pragma solidity 0.8.28;

import {Accountant} from "src/Accountant.sol";
import {IProtocolController} from "src/interfaces/IProtocolController.sol";
import {AccountantBaseTest, Math} from "test/AccountantBaseTest.t.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__Harvest is AccountantBaseTest {
    using Math for uint256;

    function test_RevertIfHarvestAndVaultsLengthNotEqual(uint256 vaultLength, uint256 harvestDataLength) external {
        // it revert if harvest and vaults length not equal

        // ensure fuzzed values are correct
        vaultLength = bound(vaultLength, 0, 6);
        harvestDataLength = bound(harvestDataLength, 0, 6);
        vm.assume(vaultLength != harvestDataLength);

        // construct vaults data
        address[] memory vaults = new address[](vaultLength);
        for (uint256 i; i < vaultLength; i++) {
            vaults[i] = address(uint160(i));
        }

        // construct harvest data
        bytes[] memory harvestData = new bytes[](harvestDataLength);
        for (uint256 i; i < harvestDataLength; i++) {
            harvestData[i] = abi.encode(i);
        }

        vm.expectRevert(Accountant.InvalidHarvestDataLength.selector);
        accountant.harvest(vaults, harvestData);
    }

    function test_RevertIfHarvesterIncorrect() external {
        // it revert if harvester incorrect

        // construct vaults/harvest data
        address[] memory vaults = new address[](1);
        bytes[] memory harvestData = new bytes[](1);

        // we mock the call to the protocol controller to return an invalid harvester
        vm.mockCall(
            address(accountant.PROTOCOL_CONTROLLER()),
            abi.encodeWithSelector(IProtocolController.strategy.selector, accountant.PROTOCOL_ID()),
            abi.encode(address(0))
        );
        vm.expectRevert(Accountant.NoStrategy.selector);

        accountant.harvest(vaults, harvestData);
    }

    function test_RevertIfRewardTokenMintReverts(uint256 rewards, uint128 amount, address _harvester)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it revert if reward token not received

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // Ensure reasonable testing data (1e24 < uint128.max)
        _assumeUnlabeledAddress(_harvester);
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        rewards = bound(rewards, accountantHarness.MIN_MEANINGFUL_REWARDS(), 1e24);

        // We are putting the contract into a state where some reward token has been mint
        // Those two functions are testing-only function that shortcut the expected flow (calling checkpoint)
        accountantHarness._cheat_updateUserData(
            vault, makeAddr("user"), Accountant.AccountData({balance: amount, integral: 0, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({integral: 0, supply: amount, feeSubjectAmount: 0, totalAmount: 0, netCredited: 0})
        );

        /// Construct realistic vaults/harvest data and call the harvest function as the _harvester
        address[] memory vaults = new address[](1);
        vaults[0] = vault;
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = abi.encode(rewards, 1e18);

        vm.mockCallRevert(
            address(rewardToken),
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(accountantHarness), rewards),
            "UNEXPECTED_ERROR_IN_ERC20"
        );

        vm.prank(_harvester);
        vm.expectRevert("UNEXPECTED_ERROR_IN_ERC20");
        accountantHarness.harvest(vaults, harvestData);
    }

    function test_RevertIfRewardTokenNotReceived(uint256 rewards, uint128 amount, address _harvester)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it revert if reward token not received

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // Ensure reasonable testing data (1e24 < uint128.max)
        _assumeUnlabeledAddress(_harvester);
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        rewards = bound(rewards, accountantHarness.MIN_MEANINGFUL_REWARDS(), 1e24);

        // We are putting the contract into a state where some reward token has been mint
        // Those two functions are testing-only function that shortcut the expected flow (calling checkpoint)
        accountantHarness._cheat_updateUserData(
            vault, makeAddr("user"), Accountant.AccountData({balance: amount, integral: 0, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({integral: 0, supply: amount, feeSubjectAmount: 0, totalAmount: 0, netCredited: 0})
        );

        /// Construct realistic vaults/harvest data and call the harvest function as the _harvester
        address[] memory vaults = new address[](1);
        vaults[0] = vault;
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = abi.encode(rewards, 1e18);

        // Next time the mint() method of the rewardToken is called
        // - It will call the mint() method of the maliciousERC20 instead
        // - The maliciousERC20 will do absolutely nothing
        // - The accountant.harvest() function MUST revert because the reward token is not received
        vm.mockFunction(
            address(rewardToken),
            address(new ERC20MaliciousMintlessToken()),
            abi.encodeWithSelector(ERC20Mock.mint.selector)
        );

        vm.prank(_harvester);
        vm.expectRevert(abi.encodeWithSelector(Accountant.HarvestTokenNotReceived.selector));
        accountantHarness.harvest(vaults, harvestData);
    }

    function test_DoesNothingIfVaultAndHarvestDataAreEmpty() external {
        // it does nothing if vault and harvest data are empty

        // construct vaults/harvest data
        address[] memory vaults = new address[](0);
        bytes[] memory harvestData = new bytes[](0);

        // start recording storage read/write before calling the function
        vm.record();
        accountant.harvest(vaults, harvestData);

        // as we expect the function to do nothing, ensure there is no storage write made
        (, bytes32[] memory writes) = vm.accesses(address(accountant));
        vm.assertEq(writes.length, 0);
    }

    function test_TransfersTheHarvestFeeToTheCallerIfThereAreSome(uint256 rewards, uint128 amount, address _harvester)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it transfers the harvest fee to the caller if there are some

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // Ensure reasonable testing data (1e24 < uint128.max)
        _assumeUnlabeledAddress(_harvester);
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        rewards = bound(rewards, accountantHarness.MIN_MEANINGFUL_REWARDS(), 1e24);

        // We are putting the contract into a state where some reward token has been mint
        // Those two functions are testing-only function that shortcut the expected flow (calling checkpoint)
        accountantHarness._cheat_updateUserData(
            vault, makeAddr("user"), Accountant.AccountData({balance: amount, integral: 0, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({integral: 0, supply: amount, feeSubjectAmount: 0, totalAmount: 0, netCredited: 0})
        );

        /// Ensure that the reward token balance is 0 before the harvest operation
        assertEq(rewardToken.balanceOf(_harvester), 0);
        assertEq(rewardToken.balanceOf(address(accountantHarness)), 0);

        /// Get the current calculated value of the harvestFee
        uint256 harvestFee = uint256(rewards).mulDiv(accountantHarness.getCurrentHarvestFee(), 1e18);

        /// Since the balance is 0, the harvest fee should be to maximum.
        assertEq(accountantHarness.getCurrentHarvestFee(), accountantHarness.getHarvestFeePercent());

        /// Construct realistic vaults/harvest data and call the harvest function as the _harvester
        address[] memory vaults = new address[](1);
        vaults[0] = vault;
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = abi.encode(rewards, 1e18);

        vm.prank(_harvester);
        accountantHarness.harvest(vaults, harvestData);

        /// Check that the reward token has been correctly dispatched
        assertEq(rewardToken.balanceOf(address(accountantHarness)), rewards - harvestFee);
        assertEq(rewardToken.balanceOf(_harvester), harvestFee);
    }

    function test_ResetVaultAmountAfterHarvesting(uint256 rewards, uint128 amount)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it reset vault amount after harvesting

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // Ensure reasonable bounds for testing (1e24 < uint128.max)
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        rewards = bound(rewards, accountantHarness.MIN_MEANINGFUL_REWARDS(), 1e24);

        // We are putting the contract into a state where some reward token has been mint
        // Those two functions are testing-only function that shortcut the expected flow (calling checkpoint)
        accountantHarness._cheat_updateUserData(
            vault, makeAddr("user"), Accountant.AccountData({balance: amount, integral: 0, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({integral: 0, supply: amount, feeSubjectAmount: 50, totalAmount: 100, netCredited: 42})
        );
        assertEq(accountantHarness.exposed_feeSubjectAmount(vault), 50);
        assertEq(accountantHarness.getPendingRewards(vault), 100);

        /// Construct realistic vaults/harvest data and call the harvest function as the _harvester
        address[] memory vaults = new address[](1);
        vaults[0] = vault;
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = abi.encode(rewards, 1e18);
        accountantHarness.harvest(vaults, harvestData);

        // ensure vault data has been reset
        assertEq(accountantHarness.exposed_feeSubjectAmount(vault), 0);
        assertEq(accountantHarness.getPendingRewards(vault), 0);
    }

    function test_UpdateVaultIntegralIfVaultStateChanged(uint256 rewards, uint128 amount)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it update vault integral if vault state changed

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // Ensure reasonable bounds for testing (1e24 < uint128.max)
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        rewards = bound(rewards, accountantHarness.MIN_MEANINGFUL_REWARDS(), 1e24);

        // We are putting the contract into a state where some reward token has been minted and vault state changed (totalAmount)
        // Those two functions are testing-only function that shortcut the expected flow (calling checkpoint)
        accountantHarness._cheat_updateUserData(
            vault, makeAddr("user"), Accountant.AccountData({balance: amount, integral: 0, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({integral: 0, supply: amount, feeSubjectAmount: 0, totalAmount: 100, netCredited: 0})
        );

        assertEq(accountantHarness.exposed_integral(vault), 0);

        /// Construct realistic vaults/harvest data and call the harvest function as the _harvester
        address[] memory vaults = new address[](1);
        vaults[0] = vault;
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = abi.encode(rewards, 1e18);
        accountantHarness.harvest(vaults, harvestData);

        // ensur vault's integral has been increased
        assertGt(accountantHarness.exposed_integral(vault), 0);
    }

    function test_EmitTheHarvestEventAfterHarvesting(uint256 rewards, uint128 amount)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it emit the harvest event after harvesting

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // Ensure reasonable bounds for testing (1e24 < uint128.max)
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        rewards = bound(rewards, accountantHarness.MIN_MEANINGFUL_REWARDS(), 1e24);

        // We are putting the contract into a state where some reward token has been mint
        // Those two functions are testing-only function that shortcut the expected flow (calling checkpoint)
        accountantHarness._cheat_updateUserData(
            vault, makeAddr("user"), Accountant.AccountData({balance: amount, integral: 0, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({integral: 0, supply: amount, feeSubjectAmount: 0, totalAmount: 0, netCredited: 0})
        );

        /// Construct realistic vaults/harvest data and call the harvest function as the _harvester
        address[] memory vaults = new address[](1);
        vaults[0] = vault;
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = abi.encode(rewards, 1e18);

        // Tell the VM we expect an event to be emitted
        // The harvested amount is equal to rewards because pendingRewards equal 0 in this scenario
        vm.expectEmit(true, true, true, true, address(accountantHarness));
        emit Accountant.Harvest(vault, rewards);

        accountantHarness.harvest(vaults, harvestData);
    }

    function test_DoesNothingIfThereIsNothingToHarvest(uint256 rewards, uint128 amount)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it cancels the harvest if there is nothing to harvest

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));

        // Ensure reasonable bounds for testing (1e24 < uint128.max)
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        rewards = bound(rewards, accountantHarness.MIN_MEANINGFUL_REWARDS(), 1e24);

        // We are putting the contract into a state where some reward token has been mint
        // Those two functions are testing-only function that shortcut the expected flow (calling checkpoint)
        accountantHarness._cheat_updateUserData(
            vault, makeAddr("user"), Accountant.AccountData({balance: amount, integral: 0, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({integral: 0, supply: amount, feeSubjectAmount: 0, totalAmount: 0, netCredited: 0})
        );

        /// Construct realistic vaults/harvest data with nothing to harvest
        address[] memory vaults = new address[](1);
        vaults[0] = vault;
        bytes[] memory harvestData = new bytes[](1);
        harvestData[0] = abi.encode(0, 1e18);

        accountantHarness.harvest(vaults, harvestData);
    }
}

contract ERC20MaliciousMintlessToken is ERC20Mock {
    constructor() ERC20Mock("Malicious ERC20", "MAL", 18) {}

    function mint(address, uint256) public override {
        // does nothing
    }
}
