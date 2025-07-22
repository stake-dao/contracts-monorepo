// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "forge-std/src/interfaces/IERC20.sol";
import {Accountant} from "src/Accountant.sol";
import {AccountantBaseTest} from "test/AccountantBaseTest.t.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";
import {AccountantHarness} from "test/unit/Accountant/AccountantHarness.t.sol";

contract Accountant__claim is AccountantBaseTest {
    function test_GivenVaultsAndHarvestBis(uint256 pendingRewards, uint256 accountantBalance)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // 1 .it uses the sender as receiver
        // 2. it reverts on reentrancy

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](1);
        vaults[0] = vault;

        // 1. check msg.sender has been used as receiver by ensuring the tokens has been transferred to him
        _setupReceiverCheck(pendingRewards, accountantBalance);
        accountant.claim(vaults, harvestData);
        assertEq(rewardToken.balanceOf(address(this)), pendingRewards);
        assertEq(rewardToken.balanceOf(address(accountant)), accountantBalance - pendingRewards);

        // 2. test the function is protected for reentrancy
        _setupReentrancy();
        accountant.claim(vaults, harvestData);
    }

    function test_GivenVaultsAndHarvestAndReceiver(
        uint256 harvestDataLength,
        uint256 pendingRewards,
        uint256 accountantBalance
    ) external _cheat_replaceAccountantWithAccountantHarness {
        // 1. it uses the sender as account
        // 2. it reverts on reentrancy
        // 3. it reverts if harvest data is non null and not equal to vaults

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](1);
        vaults[0] = vault;

        // 1. check msg.sender has been used as receiver by ensuring the tokens has been transferred to him
        _setupReceiverCheck(pendingRewards, accountantBalance);
        accountant.claim(vaults, harvestData, makeAddr("receiver"));
        assertEq(rewardToken.balanceOf(makeAddr("receiver")), pendingRewards);
        assertEq(rewardToken.balanceOf(address(accountant)), accountantBalance - pendingRewards);

        // 2. test the function is protected for reentrancy
        _setupReentrancy();
        accountant.claim(vaults, harvestData, makeAddr("receiver"));

        // 3. construct harvestData in a way the array is strictly longer than vaults
        harvestDataLength = bound(harvestDataLength, 2, 10);
        harvestData = new bytes[](harvestDataLength);
        for (uint256 i; i < harvestDataLength; i++) {
            harvestData[i] = abi.encode(i);
        }
        vm.expectRevert(Accountant.InvalidHarvestDataLength.selector);
        accountant.claim(vaults, harvestData, makeAddr("receiver"));
    }

    function test_GivenVaultsAndHarvestAndAccount(uint256 pendingRewards, uint256 accountantBalance)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // 1. it reverts on reentrancy
        // 2. it uses the account as receiver

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](1);
        vaults[0] = vault;

        // 1. check the account has been used as receiver by ensuring the tokens has been transferred to him
        _setupReceiverCheck(pendingRewards, accountantBalance);
        accountant.claim(vaults, harvestData, makeAddr("account"));
        assertEq(rewardToken.balanceOf(makeAddr("account")), pendingRewards);
        assertEq(rewardToken.balanceOf(address(accountant)), accountantBalance - pendingRewards);

        // 2. test the function is protected for reentrancy
        _setupReentrancy();
        accountant.claim(vaults, harvestData, makeAddr("account"));
    }

    function test_GivenVaultsAndAccountsAndHarvestAndReceiver(uint256 harvestDataLength)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // 1. it reverts if not allowed
        // 2. it reverts if harvest data is non null and not equal to vaults
        // 3. it reverts on reentrancy

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](1);
        vaults[0] = vault;

        // 1. test the function reverts if the caller is not allowed
        vm.expectRevert(Accountant.OnlyAllowed.selector);
        accountant.claim(vaults, makeAddr("account"), harvestData, makeAddr("receiver"));

        // 2. test the function reverts if harvest data is non null and not equal to vaults
        harvestDataLength = bound(harvestDataLength, 2, 10);
        harvestData = new bytes[](harvestDataLength);
        for (uint256 i; i < harvestDataLength; i++) {
            harvestData[i] = abi.encode(i);
        }
        vm.expectRevert(Accountant.InvalidHarvestDataLength.selector);
        _cheat_allowSender();
        accountant.claim(vaults, makeAddr("account"), harvestData, makeAddr("receiver"));

        // 3. test the function is protected for reentrancy
        // put the contract in the state it should be before calling claim for this test
        bytes[] memory harvestData2 = new bytes[](0);
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: 1e20,
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );
        accountantHarness._cheat_updateUserData(
            vault, makeAddr("account"), Accountant.AccountData({balance: 0, integral: 1e19, pendingRewards: 1e18})
        );

        _setupReentrancy();
        _cheat_allowSender();
        accountant.claim(vaults, makeAddr("account"), harvestData2, makeAddr("account"));
    }

    function test_GivenUntouchedVaultsAndAccountWithPendingRewards(
        uint256 pendingRewards,
        uint256 accountantBalance,
        uint256 integral
    ) external _cheat_replaceAccountantWithAccountantHarness {
        // 1. it send the pending rewards to the receiver
        // 2. it updates account integral with vault integral
        // 3. it reset account pending rewards

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](3);
        vaults[0] = vault;

        // make sure the accountant contract holds more token than the account for the transfer
        vm.assume(pendingRewards > 1);
        vm.assume(accountantBalance > pendingRewards);
        deal(address(rewardToken), address(accountant), accountantBalance);

        // put the contract in the state it should be before calling claim for this test
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: integral,
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );
        accountantHarness._cheat_updateUserData(
            vault,
            address(this),
            Accountant.AccountData({balance: 0, integral: integral, pendingRewards: pendingRewards})
        );

        // claim the rewards
        _cheat_allowSender();
        accountant.claim(vaults, address(this), harvestData, makeAddr("receiver"));

        // 1. check the rewards have been sent to the receiver
        assertEq(rewardToken.balanceOf(makeAddr("receiver")), pendingRewards);
        assertEq(rewardToken.balanceOf(address(accountant)), accountantBalance - pendingRewards);

        // 2. check the account integral has been updated
        assertEq(
            accountantHarness.exposed_integralUser(vault, address(this)), accountantHarness.exposed_integral(vault)
        );

        // 3. check the account pending rewards have been reset
        assertEq(accountant.getPendingRewards(vault, address(this)), 0);
    }

    /// @dev -> the inƒtegral of the vault and the user are the same and the user has no pending rewards to claim
    function test_GivenUntouchedVaultsAndAccountWithoutPendingRewards(uint256 integral)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it reverts

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](3);
        vaults[0] = vault;

        AccountantHarness(address(accountant))._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: integral,
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );
        AccountantHarness(address(accountant))._cheat_updateUserData(
            vault, address(this), Accountant.AccountData({balance: 0, integral: integral, pendingRewards: 0})
        );

        vm.expectRevert(Accountant.NoPendingRewards.selector);
        _cheat_allowSender();
        accountant.claim(vaults, address(this), harvestData, address(this));
    }

    function test_GivenUpdatedVaultsAndAccountWithoutPendingRewardsButBalance(
        uint128 accountBalance,
        uint256 accountantBalance,
        uint256 integral
    ) external _cheat_replaceAccountantWithAccountantHarness {
        // 1. it sends calculated rewards to the receiver
        // 2. it updates account integral with vault integral

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](3);
        vaults[0] = vault;
        vaults[1] = vault;
        vaults[2] = vault;

        // bound the parameters to testable values
        accountBalance = uint128(bound(accountBalance, 1e10, type(uint128).max));
        vm.assume(accountantBalance > accountBalance);
        deal(address(rewardToken), address(accountant), accountantBalance);
        integral = bound(integral, 1e18, 1e24);

        // put the contract in the state it should be before calling claim for this test
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: integral,
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );
        accountantHarness._cheat_updateUserData(
            vault, address(this), Accountant.AccountData({balance: accountBalance, integral: 0, pendingRewards: 0})
        );

        uint256 oldAccountantBalance = rewardToken.balanceOf(address(accountant));
        uint256 oldReceiverBalance = rewardToken.balanceOf(makeAddr("receiver"));

        // claim the rewards
        _cheat_allowSender();
        accountant.claim(vaults, address(this), harvestData, makeAddr("receiver"));

        // 1. check calculated rewards have been sent to the receiver
        assertGt(rewardToken.balanceOf(makeAddr("receiver")), oldReceiverBalance);
        assertLt(rewardToken.balanceOf(address(accountant)), oldAccountantBalance);

        // 2. check the account integral has been updated
        assertEq(
            accountantHarness.exposed_integralUser(vault, address(this)), accountantHarness.exposed_integral(vault)
        );
    }

    function test_GivenUpdatedVaultsAndAccountWithPendingRewardsAndBalance(
        uint128 accountBalance,
        uint256 integral,
        uint256 pendingRewards
    ) external _cheat_replaceAccountantWithAccountantHarness {
        // 1. it sends calculated and pending rewards to the receiver
        // 2. it updates account integral with vault integral
        // 3. it reset account pending rewards

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](3);
        vaults[0] = vault;

        // bound the parameters to testable values
        accountBalance = uint128(bound(accountBalance, 1e10, type(uint128).max));
        pendingRewards = bound(pendingRewards, 1e10, 1e18);
        deal(address(rewardToken), address(accountant), type(uint256).max);
        integral = bound(integral, 1e18, 1e24);

        // put the contract in the state it should be before calling claim for this test
        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        accountantHarness._cheat_updateVaultData(
            vault,
            Accountant.VaultData({
                integral: integral,
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );
        accountantHarness._cheat_updateUserData(
            vault,
            address(this),
            Accountant.AccountData({balance: accountBalance, integral: 0, pendingRewards: pendingRewards})
        );

        uint256 oldReceiverBalance = rewardToken.balanceOf(makeAddr("receiver"));

        // claim the rewards
        _cheat_allowSender();
        accountant.claim(vaults, address(this), harvestData, makeAddr("receiver"));

        // 1. check that the rewards sent to the receiver include the calculated rewards and the pending rewards
        assertGt(rewardToken.balanceOf(makeAddr("receiver")), oldReceiverBalance + pendingRewards);
        assertLt(rewardToken.balanceOf(address(accountant)), type(uint256).max);

        // 2. check the account integral has been updated
        assertEq(
            accountantHarness.exposed_integralUser(vault, address(this)), accountantHarness.exposed_integral(vault)
        );

        // 3. check the account pending rewards have been reset
        assertEq(accountant.getPendingRewards(vault, address(this)), 0);
    }

    function test_CalculatesAndSendCorrectRewardsFromMixedVaults()
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it calculates and send correct rewards from mixed vaults

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](4);
        vaults[0] = makeAddr("vault1");
        vaults[1] = makeAddr("vault2");
        vaults[2] = makeAddr("vault3");
        vaults[3] = makeAddr("vault4");

        address[] memory gauges = new address[](vaults.length);
        for (uint256 i; i < vaults.length; i++) {
            gauges[i] = vaults[i];
        }

        bytes[] memory mocks = new bytes[](gauges.length);
        for (uint256 i; i < gauges.length; i++) {
            mocks[i] = abi.encode(vaults[i]);
        }

        /// Mock the registry `vaults` used to fetch which vault is associated to a gauge and returns
        /// the vaults instead.
        vm.mockCalls(address(registry), abi.encodeWithSelector(MockRegistry.vault.selector), mocks);

        AccountantHarness accountantHarness = AccountantHarness(address(accountant));
        deal(address(rewardToken), address(accountantHarness), type(uint256).max);

        ///////////////////////
        // SETUP VAULT 1 -- vault.integral == account.integral, account.pendingRewards > 0
        ///////////////////////
        accountantHarness._cheat_updateVaultData(
            vaults[0],
            Accountant.VaultData({
                integral: uint256(1e18),
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );
        accountantHarness._cheat_updateUserData(
            vaults[0], address(this), Accountant.AccountData({balance: 0, integral: 1e18, pendingRewards: 1e12})
        );

        ///////////////////////
        // SETUP VAULT 2 -- vault.integral > account.integral, account.pendingRewards ==0, account.balance > 0
        ///////////////////////
        accountantHarness._cheat_updateVaultData(
            vaults[1],
            Accountant.VaultData({
                integral: 1e21,
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );
        accountantHarness._cheat_updateUserData(
            vaults[1], address(this), Accountant.AccountData({balance: 1e16, integral: 1e18, pendingRewards: 0})
        );

        ///////////////////////
        // SETUP VAULT 3 -- vault.integral > account.integral, account.pendingRewards > 0, account.balance > 0
        ///////////////////////
        accountantHarness._cheat_updateVaultData(
            vaults[2],
            Accountant.VaultData({
                integral: 1e21,
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );
        accountantHarness._cheat_updateUserData(
            vaults[2], address(this), Accountant.AccountData({balance: 1e17, integral: 1e18, pendingRewards: 1e18})
        );

        ///////////////////////
        // SETUP VAULT 4 -- vault.integral == account.integral, account.pendingRewards == 0, account.balance == 0
        ///////////////////////
        accountantHarness._cheat_updateVaultData(
            vaults[3],
            Accountant.VaultData({
                integral: 1e21,
                supply: 0,
                feeSubjectAmount: 0,
                totalAmount: 0,
                netCredited: 0,
                reservedHarvestFee: 0,
                reservedProtocolFee: 0
            })
        );
        accountantHarness._cheat_updateUserData(
            vaults[3], address(this), Accountant.AccountData({balance: 0, integral: 1e21, pendingRewards: 0})
        );

        // claim the rewards
        _cheat_allowSender();
        accountant.claim(gauges, address(this), harvestData, makeAddr("receiver"));

        // regression check -- if this test fails, the claim function has been modified
        uint256 expectedReceiverBalance = 10e17 + 1.10989 * 10e11;
        assertEq(rewardToken.balanceOf(makeAddr("receiver")), expectedReceiverBalance);
        assertEq(rewardToken.balanceOf(address(accountant)), type(uint256).max - expectedReceiverBalance);
    }

    function test_RevertsIfThereAreNoPendingRewards(address account, address receiver) external {
        // it reverts if there are no pending rewards

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](1);
        vaults[0] = vault;

        _cheat_allowSender();
        vm.expectRevert(Accountant.NoPendingRewards.selector);
        accountant.claim(vaults, account, harvestData, receiver);
    }

    function test_RevertsIfTheERC20TransferRevert() external _cheat_replaceAccountantWithAccountantHarness {
        // it reverts if the receiver is not compatible with ERC20

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](1);
        vaults[0] = vault;

        // 1. ensure the contract reverts if the receiver is a smart-contract not compatible with the ERC20
        _setupReceiverCheck(2, 3);

        vm.mockCallRevert(
            address(rewardToken), abi.encodeWithSelector(IERC20.transfer.selector), "ERC20_TRANSFER_REVERT"
        );
        vm.expectRevert("ERC20_TRANSFER_REVERT");
        accountant.claim(vaults, harvestData, address(2));
    }

    function test_EmitTheERC20TransferEventToTheReceiver(uint256 pendingRewards, uint256 accountantBalance)
        external
        _cheat_replaceAccountantWithAccountantHarness
    {
        // it emit the ERC20 transfer event to the receiver

        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](1);
        vaults[0] = vault;

        _setupReceiverCheck(pendingRewards, accountantBalance);

        // we tell forge to expect the OwnershipTransferred event
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(accountant), address(2), pendingRewards);

        accountant.claim(vaults, harvestData, address(2));
    }

    //////////////////////////////////////////////////////
    // --- UTILITARY FUNCTIONS
    //////////////////////////////////////////////////////

    function _cheat_allowSender() internal {
        vm.mockCall(address(registry), abi.encodeWithSelector(MockRegistry.allowed.selector), abi.encode(true));
    }

    function _setupReceiverCheck(uint256 pendingRewards, uint256 accountantBalance) internal {
        // make sure the accountant contract holds more token than the account
        vm.assume(pendingRewards > 1);
        vm.assume(accountantBalance > pendingRewards);

        // Mock reward token balance for the accountant contract
        deal(address(rewardToken), address(accountant), accountantBalance);

        // we modify the state of the account by in the accountant contract, shortcuting the real process
        AccountantHarness(address(accountant))._cheat_updateUserData(
            vault, address(this), Accountant.AccountData({balance: 0, integral: 0, pendingRewards: pendingRewards})
        );
    }

    function _setupReentrancy() internal {
        // // we modify the state of the account by in the accountant contract, shortcuting the real process
        AccountantHarness(address(accountant))._cheat_updateUserData(
            vault, address(this), Accountant.AccountData({balance: 0, integral: 0, pendingRewards: 1})
        );

        // // Next time the transfer() method of the reward token contract is called
        // // - It will call the transfer() method of the maliciousContract instead
        // // - The maliciousContract will call the accountant.claim() function again in the same tx
        // // - The accountant.claim() function MUST revert to ensure we are safe from reentrancy
        ERC20MockMaliciousReeantrancy maliciousContract = new ERC20MockMaliciousReeantrancy(vault);
        vm.mockFunction(
            address(rewardToken), address(maliciousContract), abi.encodeWithSelector(IERC20.transfer.selector)
        );

        // // we tell the VM we expect the next call to revert with the exact reentrancy error
        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector));
    }
}

contract ERC20MockMaliciousReeantrancy is AccountantBaseTest {
    address private immutable vaultToAttack;

    constructor(address _vaultToAttack) {
        vaultToAttack = _vaultToAttack;
    }

    // this is a malicious transfer() function that will recall accountant.claimProtocolFees()
    function transfer(address, uint256) external returns (bool) {
        bytes[] memory harvestData = new bytes[](0);
        address[] memory vaults = new address[](1);
        vaults[0] = vaultToAttack;

        Accountant(msg.sender).claim(vaults, harvestData);
        // expected to never reach this point because the call above MUST revert
        return false;
    }
}
