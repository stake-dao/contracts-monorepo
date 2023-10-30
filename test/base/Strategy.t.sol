// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/base/strategy/Strategy.sol";
import "src/base/vault/StrategyVaultImpl.sol";

abstract contract StrategyTest is Test {
    modifier testDeposit(StrategyVaultImpl vault, Strategy strategy) {
        _;
    }

    modifier testWithdraw(StrategyVaultImpl vault, Strategy strategy) {
        _;
    }

    modifier testHarvest(StrategyVaultImpl vault, Strategy strategy) {
        _;
    }

    modifier testFeeAccounting(StrategyVaultImpl vault, Strategy strategy) {
        _;
    }
}
