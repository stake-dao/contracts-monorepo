// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {YieldnestProtocol} from "address-book/src/YieldnestEthereum.sol";
import {Test} from "forge-std/src/Test.sol";
import {YieldnestAutocompoundedVault} from "src/integrations/yieldnest/YieldnestAutocompoundedVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract asdYNDTest is Test {
    YieldnestAutocompoundedVault internal vault;
    address internal owner = makeAddr("owner");
    address internal manager = makeAddr("manager");
    address internal gauge = YieldnestProtocol.GAUGE;
    IERC20 internal asset = IERC20(YieldnestProtocol.SDYND);

    function setUp() external {
        vm.createSelectFork("mainnet", 22_646_185);

        // Deploy the ERC4626 vault
        vault = new YieldnestAutocompoundedVault(owner, gauge, manager);

        // Labels important addresses
        vm.label(address(asset), "asset");
        vm.label(address(vault), "AutocompoundedVault");
        vm.label(owner, "owner");
        vm.label(manager, "manager");
        vm.label(gauge, "gauge");
    }

    function test_deposit() public returns (address[2] memory holders, uint256[2] memory initialBalances) {
        holders = [0x0329aCa1a15139e2288E58c8a8a057b7723af4f2, 0xE80F70B360d049E5060b5CCE54BA38808334d633];
        initialBalances = [asset.balanceOf(holders[0]), asset.balanceOf(holders[1])];

        for (uint256 i; i < holders.length; i++) {
            address holder = holders[i];
            uint256 balance = asset.balanceOf(holder);

            uint256 gaugeBeforeBalance = asset.balanceOf(gauge);
            uint256 vaultBeforeBalance = IERC20(gauge).balanceOf(address(vault));

            vm.prank(holder);
            asset.approve(address(vault), balance);

            // Deposit the assets into the vault
            vm.prank(holder);
            uint256 sharesReceived = vault.deposit(balance, holder);

            // Assert that the shares received are equal to the deposit amount
            assertEq(sharesReceived, balance);
            assertEq(vault.balanceOf(holder), balance);
            assertEq(asset.balanceOf(holder), 0);

            // Asssert the gauge holds the assets
            uint256 gaugeAfterBalance = asset.balanceOf(gauge);
            assertEq(gaugeAfterBalance, gaugeBeforeBalance + balance);

            // Assert the vault holds the gauge tokens
            uint256 vaultAfterBalance = IERC20(gauge).balanceOf(address(vault));
            assertEq(vaultAfterBalance, vaultBeforeBalance + balance);
        }
    }

    function test_withdraw() external {
        (address[2] memory holders, uint256[2] memory initialBalances) = test_deposit();

        // 1. withdraw all shares with the first account before the rewards stream starts
        address holder = holders[0];
        uint256 balance = initialBalances[0];

        vm.prank(holder);
        vault.approve(address(vault), vault.balanceOf(holder));

        uint256 maxWithdraw = vault.maxWithdraw(holder);
        vm.prank(holder);
        vault.withdraw(maxWithdraw, holder, holder);

        // 2. ensure the first account received the same amount he deposited to the vault
        assertEq(asset.balanceOf(holder), balance);

        // 3. airdrop some asset to the manager
        uint256 rewards = 1e22;
        deal(YieldnestProtocol.SDYND, manager, rewards);

        // 4. set a new rewards stream for the vault
        vm.prank(manager);
        asset.approve(address(vault), rewards);
        vm.prank(manager);
        vault.setRewardsStream(rewards);

        // 5. jump after the rewards stream ends
        vm.warp(block.timestamp + vault.STREAMING_PERIOD());

        // 6. withdraw all shares with the second account
        holder = holders[1];
        balance = initialBalances[1];
        maxWithdraw = vault.maxWithdraw(holder);
        vm.prank(holder);
        vault.withdraw(maxWithdraw, holder, holder);

        // 7. ensure the second account received the initial balance + the full rewards (+/- 1% due to rounding)
        assertApproxEqAbs(asset.balanceOf(holder), balance + rewards, 1e16);
    }

    function test_yield() external {
        address holder = 0x0329aCa1a15139e2288E58c8a8a057b7723af4f2;
        uint256 balance = asset.balanceOf(holder);

        // 1. deposit some assets into the vault
        vm.prank(holder);
        asset.approve(address(vault), balance);
        vm.prank(holder);
        vault.deposit(balance, holder);

        // sequentially start and complete several reward streams with no overlapping
        uint256[3] memory rewards;
        rewards[0] = 1e22;
        rewards[1] = 1e19;
        rewards[2] = 1e24;
        for (uint256 i; i < rewards.length; i++) {
            deal(address(asset), manager, rewards[i]);

            vm.prank(manager);
            asset.approve(address(vault), rewards[i]);

            vm.prank(manager);
            vault.setRewardsStream(rewards[i]);

            vm.warp(block.timestamp + vault.STREAMING_PERIOD());
        }

        // withdraw the max share with the holder
        vm.prank(holder);
        vault.approve(address(vault), vault.balanceOf(holder));
        uint256 maxWithdraw = vault.maxWithdraw(holder);
        vm.prank(holder);
        vault.withdraw(maxWithdraw, holder, holder);

        // assert the holder received the initial balance + the full rewards (+/- 1% due to rounding)
        assertApproxEqAbs(asset.balanceOf(holder), balance + rewards[0] + rewards[1] + rewards[2], 1e16);
    }

    function test_migration() external {
        // holder of the gauge token before the migration of the vault
        address holder = 0x4c47b2520E9f7E3da15dF09718d467f783b03858;
        uint256 balance = IERC20(gauge).balanceOf(holder);

        // assert the holder has some gauge tokens, no asset and no shares
        assertNotEq(balance, 0);
        assertEq(asset.balanceOf(holder), 0);
        assertEq(vault.balanceOf(holder), 0);
        uint256 vaultBeforeBalance = IERC20(gauge).balanceOf(address(vault));

        // give approval to the vault to transfer the gauge tokens
        vm.prank(holder);
        IERC20(gauge).approve(address(vault), balance);

        // get the expected amount of shares
        uint256 shares = vault.previewDeposit(balance);

        vm.expectEmit(true, true, true, true);
        emit YieldnestAutocompoundedVault.GaugeTokenMigrated(holder, balance, shares);

        // deposit the gauge tokens to the vault
        vm.prank(holder);
        vault.depositFromGauge();

        // the holder doesn't have any gauge tokens
        assertEq(IERC20(gauge).balanceOf(holder), 0);
        // the holder doesn't have any asset (sdYND)
        assertEq(asset.balanceOf(holder), 0);
        // the holder now holds the expected amount of vault shares (asdYND)
        assertEq(vault.balanceOf(holder), balance);
        // the vault now holds the expected amount of gauge tokens
        assertEq(IERC20(gauge).balanceOf(address(vault)), vaultBeforeBalance + balance);
    }

    function test_migrationReceiver() external {
        // holder of the gauge token before the migration of the vault
        address holder = 0x4c47b2520E9f7E3da15dF09718d467f783b03858;
        uint256 balance = IERC20(gauge).balanceOf(holder);
        address receiver = makeAddr("receiver");

        // assert the holder has some gauge tokens, no asset and no shares
        assertNotEq(balance, 0);
        assertEq(asset.balanceOf(holder), 0);
        assertEq(asset.balanceOf(receiver), 0);
        assertEq(vault.balanceOf(holder), 0);
        assertEq(vault.balanceOf(receiver), 0);

        // give approval to the vault to transfer the gauge tokens
        vm.prank(holder);
        IERC20(gauge).approve(address(vault), balance);

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Deposit(holder, receiver, balance, balance);

        // deposit the gauge tokens to the vault
        vm.prank(holder);
        vault.depositFromGauge(receiver);

        // the gauge tokens are now in the vault
        assertEq(IERC20(gauge).balanceOf(holder), 0);
        assertEq(IERC20(gauge).balanceOf(receiver), 0);
        // the assets are now in the gauge
        assertEq(asset.balanceOf(holder), 0);
        assertEq(asset.balanceOf(receiver), 0);
        // the holder received no vault shares
        assertEq(vault.balanceOf(holder), 0);
        // the receiver now has the vault shares
        assertEq(vault.balanceOf(receiver), balance);
    }
}
