// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {YieldnestProtocol} from "address-book/src/YieldnestEthereum.sol";
import {Test} from "forge-std/src/Test.sol";
import {YieldnestAutocompoundedVault} from "src/integrations/yieldnest/YieldnestAutocompoundedVault.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {ProtocolController} from "src/ProtocolController.sol";

contract asdYNDTest is Test {
    YieldnestAutocompoundedVault internal vault;
    address internal protocolController;

    // Accounts to test the vault with
    address[2] internal holders =
        [0x26aB50DC99F14405155013ea580Ea2b3dB1801c7, 0x52ea58f4FC3CEd48fa18E909226c1f8A0EF887DC];
    uint256[2] internal balances = [105e18, 10e18];

    function setUp() external {
        vm.createSelectFork("mainnet", 22_567_990);

        // Deploy a the protocol controller
        protocolController = address(new MockProtocolController());

        // Deploy the ERC4626 vault
        vault = new YieldnestAutocompoundedVault(protocolController);

        // Labels important addresses
        vm.label(protocolController, "Protocol Controller");
        vm.label(YieldnestProtocol.SDYND, "sdYND");
        vm.label(address(vault), "AutocompoundedVault");
    }

    function test_deposit() public {
        for (uint256 i; i < holders.length; i++) {
            // Approve the vault to spend the tokens

            // uint256 balance = ERC20Mock(YieldnestProtocol.SDYND).balanceOf(holders[i]);
            vm.prank(holders[i]);
            ERC20Mock(YieldnestProtocol.SDYND).approve(address(vault), balances[i]);

            // Deposit the tokens into the vault
            vm.prank(holders[i]);
            uint256 sharesReceived = vault.deposit(balances[i], holders[i]);

            // Assert that the shares received are equal to the deposit amount
            assertEq(sharesReceived, balances[i]);
            assertEq(vault.balanceOf(holders[i]), balances[i]);
            assertEq(ERC20Mock(YieldnestProtocol.SDYND).balanceOf(holders[i]), 0);
        }
    }

    function test_withdraw() external {
        test_deposit();

        // 1. withdraw all shares with the first account before the rewards stream starts
        uint256 maxWithdraw = vault.maxWithdraw(holders[0]);
        vm.prank(holders[0]);
        vault.withdraw(maxWithdraw, holders[0], holders[0]);

        // 2. ensure the first account received the same amount he deposited to the vault
        assertEq(ERC20Mock(YieldnestProtocol.SDYND).balanceOf(holders[0]), balances[0]);

        // 3. airdrop some sdYND to this contract
        uint256 rewards = 1e12;
        deal(YieldnestProtocol.SDYND, address(this), rewards);

        // 4. mock the protocol controller to allow this contract to set some rewards
        vm.mockCall(protocolController, abi.encodeWithSelector(ProtocolController.allowed.selector), abi.encode(true));

        // 5. set a new rewards stream for the vault
        ERC20Mock(YieldnestProtocol.SDYND).approve(address(vault), rewards);
        vm.prank(address(this));
        vault.setRewards(rewards);

        // 6. jump after the rewards stream ends
        vm.warp(block.timestamp + vault.STREAMING_PERIOD());

        // 7. withdraw all shares with the second account
        maxWithdraw = vault.maxWithdraw(holders[1]);
        vm.prank(holders[1]);
        vault.withdraw(maxWithdraw, holders[1], holders[1]);

        // 8. ensure the second account received the initial balance + the full rewards (+/- 1% due to rounding)
        assertApproxEqAbs(ERC20Mock(YieldnestProtocol.SDYND).balanceOf(holders[1]), balances[1] + rewards, 1e16);
    }
}

contract MockProtocolController {
    function allowed(address, address, bytes4) external pure returns (bool) {
        return false;
    }
}
