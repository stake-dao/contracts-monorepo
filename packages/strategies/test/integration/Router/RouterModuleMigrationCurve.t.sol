// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {
    RouterModuleMigrationCurve__migrate,
    MockCurveLiquidityGauge as CurveLiquidityGauge
} from "test/unit/Router/RouterModules/RouterModuleMigrationCurve/migrate.t.sol";

/// @notice Extends the unit test with integration tests for the forked mainnet parameters
contract RouterModuleMigrationCurveFork is RouterModuleMigrationCurve__migrate {
    function setUp() public override {
        vm.createSelectFork("mainnet", 22_275_265);

        super.setUp();
    }

    function test_fork_migratesTheTokenFromTheLiquidityGaugeToTheRewardVault() external {
        // it migrates the token from the liquidity gauge to the reward vault

        // random holder
        address account = 0x826F5CcDB20044CaF36e31328652c4396bf01E65;
        vm.label({account: account, newLabel: "account"});

        // store the liquidity gauge
        from = CurveLiquidityGauge(0x4e6bB6B7447B7B2Aa268C16AB87F4Bb48BF57939);
        vm.label({account: address(from), newLabel: "Curve Liquidity Gauge"});

        // store the asset used by the liquidity gauge
        asset = from.lp_token();
        vm.label({account: asset, newLabel: "asset"});

        assertNotEq(from.balanceOf(account), 0);

        // ------------------------------------------------------------

        _test_token_migration(account, from.balanceOf(account));
    }
}
