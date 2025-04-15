// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    RouterModuleMigrationStakeDAOV1__migrate,
    MockVault as StakeDAOVault
} from "test/unit/Router/RouterModules/RouterModuleMigrationStakeDAOV1/migrate.t.sol";

/// @notice Extends the unit test with integration tests for the forked mainnet parameters
contract RouterModuleMigrationStakeDAOV1Fork is RouterModuleMigrationStakeDAOV1__migrate {
    function setUp() public override {
        vm.createSelectFork("mainnet", 22_275_265);

        super.setUp();
    }

    function test_fork_migratesTheTokenFromTheVaultToTheRewardVault() external {
        // it migrates the token from the vault to the reward vault

        // random holder
        address account = 0xA585a2096314a6FD183196c5C62B73d1B28656E7;
        vm.label({account: account, newLabel: "account"});

        // store the vault
        from = StakeDAOVault(0x08d0Ce415bE57805209B41d438984ea0814910a8);
        vm.label({account: address(from), newLabel: "Stake DAO Vault"});

        // store the asset used by the vault
        asset = from.token();
        vm.label({account: asset, newLabel: "asset"});

        uint256 balance = IERC20(from.liquidityGauge()).balanceOf(account);

        assertNotEq(balance, 0);

        // ------------------------------------------------------------

        _test_token_migration(account, balance);
    }
}
