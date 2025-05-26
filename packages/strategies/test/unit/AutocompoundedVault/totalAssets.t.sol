// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {AutocompoundedVault} from "src/integrations/yieldnest/AutocompoundedVault.sol";
import {AutocompoundedVaultTest} from "test/unit/AutocompoundedVault/utils/AutocompoundedVaultTest.t.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract AutocompoundedVault__totalAssets is AutocompoundedVaultTest {
    AutocompoundedVault internal autocompoundedVault;

    function setUp() public override {
        super.setUp();

        autocompoundedVault = new AutocompoundedVault(address(protocolController));
        vm.label(address(autocompoundedVault), "AutocompoundedVault");
    }

    function test_ReturnsTheRealBalanceWhenThereIsNoStream(uint256 balance) external {
        // it returns the real balance when there is no stream

        balance = bound(balance, 1e12, 1e30);

        // airdrop some assets to the vault
        deal(autocompoundedVault.asset(), address(autocompoundedVault), balance);

        assertEq(autocompoundedVault.totalAssets(), balance);
    }

    function test_ReturnsTheRealBalanceMinusTheUnvestedPortionWhenThereIsAStream(
        uint256 initialBalance,
        uint256 rewards
    ) external {
        // it returns the real balance minus the unvested portion when there is a stream

        initialBalance = bound(initialBalance, 1e12, 1e18);
        rewards = bound(rewards, 1e12, 1e18);
        uint256 initialTimestamp = block.timestamp;

        // airdrop some assets to the vault
        deal(autocompoundedVault.asset(), address(autocompoundedVault), initialBalance);

        // set a reward stream
        deal(autocompoundedVault.asset(), address(this), rewards);
        IERC20(autocompoundedVault.asset()).approve(address(autocompoundedVault), rewards);
        autocompoundedVault.setRewards(rewards);

        // warp to a quarter of the streaming period and assert the total assets (+/- 1% due to the precision of the division)
        (,,,, uint128 streamDuration) = autocompoundedVault.getCurrentStream();
        vm.warp(initialTimestamp + streamDuration / 4);
        assertApproxEqRel(autocompoundedVault.totalAssets(), initialBalance + rewards / 4, 1e16);

        // warp to half of the streaming period and assert the total assets (+/- 1% due to the precision of the division)
        vm.warp(initialTimestamp + streamDuration / 2);
        assertApproxEqRel(autocompoundedVault.totalAssets(), initialBalance + rewards / 2, 1e16);

        // warp to the end of the streaming period and assert the total assets
        vm.warp(initialTimestamp + streamDuration);
        assertEq(autocompoundedVault.totalAssets(), initialBalance + rewards);

        // warp to a future timestamp and assert the total assets didn't change and is equal to the real balance
        vm.warp(initialTimestamp + streamDuration * 3 / 2);
        assertEq(autocompoundedVault.totalAssets(), initialBalance + rewards);
        assertEq(
            autocompoundedVault.totalAssets(),
            IERC20(autocompoundedVault.asset()).balanceOf(address(autocompoundedVault))
        );
    }
}
