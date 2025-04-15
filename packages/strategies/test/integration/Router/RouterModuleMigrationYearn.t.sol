// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {
    RouterModuleMigrationYearn__migrate,
    MockYearnVault as YearnVault
} from "test/unit/Router/RouterModules/RouterModuleMigrationYearn/migrate.t.sol";

/// @notice Extends the unit test with integration tests for the forked mainnet parameters
contract RouterModuleMigrationYearnFork is RouterModuleMigrationYearn__migrate {
    function setUp() public virtual override {
        vm.createSelectFork("mainnet", 22_275_265);

        super.setUp();
    }

    function test_fork_migratesTheTokenFromTheVaultToTheRewardVault() external {
        // it migrates the token from the vault to the reward vault

        // random holder
        address account = 0xdB2B9D473014d8c6A5E55dA92205199457Ba6624;
        vm.label({account: account, newLabel: "account"});

        // store the vault
        from = YearnVault(0x27B5739e22ad9033bcBf192059122d163b60349D);
        vm.label({account: address(from), newLabel: "Yearn Vault"});

        // store the asset used by the vault
        asset = from.token();
        vm.label({account: asset, newLabel: "asset"});

        assertNotEq(from.balanceOf(account), 0);

        // ------------------------------------------------------------

        _test_token_migration(account, from.balanceOf(account));
    }
}
