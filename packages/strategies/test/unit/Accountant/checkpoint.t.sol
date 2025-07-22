// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Accountant} from "src/Accountant.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {AccountantBaseTest, MockRegistry} from "test/AccountantBaseTest.t.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__checkpoint is AccountantBaseTest {
    function test_RevertIfNotCalledByTheVault(address caller) external {
        // it revert if not called by the vault

        vm.assume(caller != registry.vault(address(stakingToken)));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Accountant.OnlyVault.selector));
        accountant.checkpoint(
            makeAddr("asset"),
            makeAddr("from"),
            makeAddr("to"),
            5,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            IStrategy.HarvestPolicy.HARVEST,
            address(0)
        );
    }

    function test_RevertIfReentrancy() external {
        // it revert if reentrancy

        // deploy the malicious registry that will perform the reentrancy attack
        MaliciousRegistry maliciousRegistry = new MaliciousRegistry(
            makeAddr("asset"),
            makeAddr("from"),
            makeAddr("to"),
            5,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            IStrategy.HarvestPolicy.HARVEST
        );

        // mock the call to the Registry. Next time the vaults() method of the registry is called
        // - It will call the vaults() method of the maliciousRegistry instead
        // - The maliciousERC20 will call the accountant.checkpoint() function again in the same tx
        // - The accountant.checkpoint() function MUST revert to ensure we are safe from reentrancy
        vm.mockFunction(
            address(registry), address(maliciousRegistry), abi.encodeWithSelector(MaliciousRegistry.vault.selector)
        );

        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector));
        accountant.checkpoint(
            makeAddr("asset"),
            makeAddr("from"),
            makeAddr("to"),
            5,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            IStrategy.HarvestPolicy.HARVEST,
            address(0)
        );
    }

    modifier whenThereAreSomePendingRewardsAndAPositiveSupply() {
        _;
    }

    function test_GivenSomeNewRewardsAndInitialSupplyAndHarvestedSetToTrue(
        uint128 amount,
        uint128 initialSupply,
        uint256 vaultIntegral
    ) external _cheat_replaceAccountantWithAccountantHarness whenThereAreSomePendingRewardsAndAPositiveSupply {
        // it updates the fee subject amount
        // it updates the protocol fees acrued if there are new fee subject amount
        // it updates the vault integral

        // We bound the parameters into realistic ranges. Those parameters lead to non-null pending rewards for the account
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        vaultIntegral = bound(vaultIntegral, 1e20, 1e28);
        initialSupply = uint128(bound(uint256(initialSupply), 1, type(uint128).max - amount - 1));

        // We put the contract into an initial state
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: vaultIntegral,
                supply: initialSupply,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );

        uint256 beforeProtocolFeesAccrued = accountant.protocolFeesAccrued();
        uint256 beforeVaultIntegral = accountantHarness.exposed_integral(vault);

        vm.prank(vault);
        accountant.checkpoint(
            makeAddr("asset"),
            address(0),
            makeAddr("account"),
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 1e29, totalAmount: 2e29}),
            IStrategy.HarvestPolicy.HARVEST,
            address(0)
        );

        assertLt(beforeProtocolFeesAccrued, accountant.protocolFeesAccrued());
        assertLt(beforeVaultIntegral, accountantHarness.exposed_integral(vault));
    }

    function test_GivenTheNewRewardsAreHigherThanTheMinimum(
        uint128 amount,
        uint128 initialSupply,
        uint256 vaultIntegral,
        uint128 pendingTotalAmount
    ) external _cheat_replaceAccountantWithAccountantHarness whenThereAreSomePendingRewardsAndAPositiveSupply {
        // it updates the vault rewards
        // it updates the fee subject amount
        // it updates vault and user integral
        // it uses the new fee subject amount to calculate the total fees if there are some

        // We bound the parameters into realistic ranges. Those parameters lead to non-null pending rewards for the account
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        vaultIntegral = bound(vaultIntegral, 1e20, 1e28);
        initialSupply = uint128(bound(uint256(initialSupply), 1, type(uint128).max - amount - 1));
        vm.assume(pendingTotalAmount >= accountant.MIN_MEANINGFUL_REWARDS());

        // We put the contract into an initial state
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: vaultIntegral,
                supply: initialSupply,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );

        uint256 beforePendingRewards = accountant.getPendingRewards(vault);
        uint256 beforeFeeSubjectAmount = accountantHarness.exposed_feeSubjectAmount(vault);
        uint256 beforeVaultIntegral = accountantHarness.exposed_integral(vault);
        uint256 beforeUserIntegral = accountantHarness.exposed_integralUser(vault, makeAddr("account"));

        vm.prank(vault);
        accountant.checkpoint(
            makeAddr("asset"),
            address(0),
            makeAddr("account"),
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: pendingTotalAmount / 100, totalAmount: pendingTotalAmount}),
            IStrategy.HarvestPolicy.CHECKPOINT,
            address(0)
        );

        assertLt(beforePendingRewards, accountant.getPendingRewards(vault));
        assertLt(beforeFeeSubjectAmount, accountantHarness.exposed_feeSubjectAmount(vault));
        assertLt(beforeVaultIntegral, accountantHarness.exposed_integral(vault));
        assertLt(beforeUserIntegral, accountantHarness.exposed_integralUser(vault, makeAddr("account")));
    }

    function test_GivenFromIs0(
        uint128 amount,
        uint128 initialSupply,
        uint128 initialUserBalance,
        uint256 vaultIntegral,
        uint256 userIntegral
    ) external _cheat_replaceAccountantWithAccountantHarness {
        // it adds the given amount to the vault supply
        // it updates the pending rewards of the account
        // it increases the balance of the account
        // it updates the integral of the account

        // We bound the parameters into realistic ranges. Those parameters lead to non-null pending rewards for the account
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        vm.assume(type(uint128).max - amount > initialSupply);
        initialUserBalance = uint128(bound(uint256(amount), 1e8, 1e20));
        vm.assume(type(uint128).max - amount > initialUserBalance);
        vaultIntegral = bound(vaultIntegral, 1e20, 1e28);
        userIntegral = bound(userIntegral, 1e12, 1e16);
        address account = makeAddr("account");

        // We put the contract into an initial state
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        accountantHarness._cheat_updateUserData(
            vault,
            account,
            Accountant.AccountData({balance: initialUserBalance, integral: userIntegral, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: vaultIntegral,
                supply: initialSupply,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );

        // we call the checkpoint function to mint new tokens
        vm.prank(vault);
        accountant.checkpoint(
            makeAddr("asset"),
            address(0),
            account,
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            IStrategy.HarvestPolicy.CHECKPOINT,
            address(0)
        );

        assertEq(accountant.totalSupply(vault), initialSupply + amount);
        assertEq(accountant.balanceOf(vault, account), initialUserBalance + amount);
        assertGt(accountant.getPendingRewards(vault, account), 0);
        assertEq(accountantHarness.exposed_integralUser(vault, account), accountantHarness.exposed_integral(vault));
    }

    function test_GivenToIs0(
        uint128 amount,
        uint128 initialSupply,
        uint128 initialUserBalance,
        uint256 vaultIntegral,
        uint256 userIntegral
    ) external _cheat_replaceAccountantWithAccountantHarness {
        // it substract the given amount to the vault supply
        // it decreases the balance of the account
        // it updates the pending rewards of the account
        // it updates the integral of the account

        // We bound the parameters into realistic ranges. Those parameters lead to non-null pending rewards for the account
        amount = uint128(bound(uint256(amount), 1e6, 1e24));
        vm.assume(type(uint128).max - amount > initialSupply);
        initialUserBalance = uint128(bound(uint256(amount), 1e8, 1e20));
        vm.assume(type(uint128).max - amount > initialUserBalance);
        vaultIntegral = bound(vaultIntegral, 1e20, 1e28);
        userIntegral = bound(userIntegral, 1e12, 1e16);
        address account = makeAddr("account");

        // We put the contract into an initial state
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        accountantHarness._cheat_updateUserData(
            vault,
            account,
            Accountant.AccountData({balance: initialUserBalance + amount, integral: userIntegral, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: vaultIntegral,
                supply: initialSupply + amount,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );

        // we call the checkpoint function to burn the previously held tokens
        vm.prank(vault);
        accountant.checkpoint(
            makeAddr("asset"),
            account,
            address(0),
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            IStrategy.HarvestPolicy.CHECKPOINT,
            address(0)
        );

        assertEq(accountant.totalSupply(vault), initialSupply);
        assertEq(accountant.balanceOf(vault, account), initialUserBalance);
        assertGt(accountant.getPendingRewards(vault, account), 0);
        assertEq(accountantHarness.exposed_integralUser(vault, account), accountantHarness.exposed_integral(vault));
    }

    function test_GivenFromAndToAre0(
        uint128 amount,
        uint128 initialSupply,
        uint128 initialUserBalance,
        uint256 vaultIntegral,
        uint256 userIntegral
    ) external _cheat_replaceAccountantWithAccountantHarness {
        // it do not update the vault supply
        // it do not update the state of the account

        // We bound the parameters into realistic ranges.
        vm.assume(type(uint128).max - amount > initialSupply);
        address account = makeAddr("account");

        // We put the contract into an initial state
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        accountantHarness._cheat_updateUserData(
            vault,
            account,
            Accountant.AccountData({balance: initialUserBalance, integral: userIntegral, pendingRewards: 0})
        );
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: vaultIntegral,
                supply: initialSupply,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );

        // we call the checkpoint function to mint new tokens
        vm.prank(vault);
        accountant.checkpoint(
            makeAddr("asset"),
            address(0),
            address(0),
            amount,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            IStrategy.HarvestPolicy.CHECKPOINT,
            address(0)
        );

        assertEq(accountant.totalSupply(vault), initialSupply);
        assertEq(accountant.balanceOf(vault, account), initialUserBalance);
        assertEq(accountant.getPendingRewards(vault, account), 0);
        assertEq(accountantHarness.exposed_integralUser(vault, account), userIntegral);
        assertEq(accountantHarness.exposed_integral(vault), vaultIntegral);
    }

    function test_RevertsWhenTheRegistryReverts(bool harvested) external {
        // it reverts when the registry reverts
        IStrategy.HarvestPolicy policy =
            harvested ? IStrategy.HarvestPolicy.HARVEST : IStrategy.HarvestPolicy.CHECKPOINT;

        // mock the call to the registry.vaults and force it to revert
        vm.mockCallRevert(
            address(registry),
            abi.encodeWithSelector(MockRegistry.vault.selector, address(stakingToken)),
            "UNCONTROLLED_SD_ERROR"
        );

        // If the registry revert, it returns the default address value (address(0))
        // which is not the msg.sender, meaning the require condition breaks
        vm.expectRevert(abi.encodeWithSelector(Accountant.OnlyVault.selector));
        accountant.checkpoint(
            makeAddr("asset"),
            makeAddr("from"),
            makeAddr("to"),
            5,
            IStrategy.PendingRewards({feeSubjectAmount: 0, totalAmount: 0}),
            policy,
            address(0)
        );
    }
}

/// @notice this contrat is used to test our protection against a reentrancy attack
contract MaliciousRegistry {
    struct AttackData {
        address asset;
        address from;
        address to;
        uint128 amount;
        IStrategy.PendingRewards pendingRewards;
        IStrategy.HarvestPolicy policy;
    }

    AttackData private attackData;

    constructor(
        address asset,
        address from,
        address to,
        uint128 amount,
        IStrategy.PendingRewards memory pendingRewards,
        IStrategy.HarvestPolicy policy
    ) {
        attackData = AttackData(asset, from, to, amount, pendingRewards, policy);
    }

    // this is a malicious transfer() function that will recall accountant.claimProtocolFees()
    function vault(address) public returns (address) {
        Accountant(msg.sender).checkpoint(
            attackData.asset,
            attackData.from,
            attackData.to,
            attackData.amount,
            attackData.pendingRewards,
            attackData.policy,
            address(0)
        );
        // expected to never reach this point because the call above MUST revert
        return address(0);
    }
}
