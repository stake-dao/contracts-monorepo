// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {YieldnestLocker} from "@address-book/src/YieldnestEthereum.sol";
import {Test} from "forge-std/src/Test.sol";
import {YieldnestAutocompoundedVault} from "src/integrations/yieldnest/YieldnestAutocompoundedVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract asdYNDTest is Test {
    YieldnestAutocompoundedVault internal vault;
    address internal owner = makeAddr("owner");

    // Accounts to test the vault with
    address[2] internal holders =
        [0x26aB50DC99F14405155013ea580Ea2b3dB1801c7, 0x52ea58f4FC3CEd48fa18E909226c1f8A0EF887DC];
    uint256[2] internal balances = [105e18, 10e18];

    function setUp() external {
        vm.createSelectFork("mainnet", 22_567_990);

        // Deploy the ERC4626 vault
        vault = new YieldnestAutocompoundedVault(owner);

        // Labels important addresses
        vm.label(YieldnestLocker.SDYND, "sdYND");
        vm.label(address(vault), "AutocompoundedVault");
        vm.label(owner, "owner");
    }

    function test_deposit() public {
        for (uint256 i; i < holders.length; i++) {
            // Approve the vault to spend the tokens

            // uint256 balance = ERC20Mock(YieldnestLocker.SDYND).balanceOf(holders[i]);
            vm.prank(holders[i]);
            ERC20(YieldnestProtocol.SDYND).approve(address(vault), balances[i]);

            // Deposit the tokens into the vault
            vm.prank(holders[i]);
            uint256 sharesReceived = vault.deposit(balances[i], holders[i]);

            // Assert that the shares received are equal to the deposit amount
            assertEq(sharesReceived, balances[i]);
            assertEq(vault.balanceOf(holders[i]), balances[i]);
            assertEq(ERC20(YieldnestProtocol.SDYND).balanceOf(holders[i]), 0);
        }
    }

    function test_withdraw() external {
        test_deposit();

        // 1. withdraw all shares with the first account before the rewards stream starts
        uint256 maxWithdraw = vault.maxWithdraw(holders[0]);
        vm.prank(holders[0]);
        vault.withdraw(maxWithdraw, holders[0], holders[0]);

        // 2. ensure the first account received the same amount he deposited to the vault
        assertEq(ERC20(YieldnestProtocol.SDYND).balanceOf(holders[0]), balances[0]);

        // 3. airdrop some sdYND to the owner
        uint256 rewards = 1e12;
        deal(YieldnestLocker.SDYND, owner, rewards);

        // 4. set a new rewards stream for the vault
        vm.prank(owner);
        ERC20(YieldnestProtocol.SDYND).approve(address(vault), rewards);
        vm.prank(owner);
        vault.setRewards(rewards);

        // 5. jump after the rewards stream ends
        vm.warp(block.timestamp + vault.STREAMING_PERIOD());

        // 6. withdraw all shares with the second account
        maxWithdraw = vault.maxWithdraw(holders[1]);
        vm.prank(holders[1]);
        vault.withdraw(maxWithdraw, holders[1], holders[1]);

        // 7. ensure the second account received the initial balance + the full rewards (+/- 1% due to rounding)
        assertApproxEqAbs(ERC20(YieldnestProtocol.SDYND).balanceOf(holders[1]), balances[1] + rewards, 1e16);
    }
}
