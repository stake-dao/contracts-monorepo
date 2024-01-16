// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";


import {PendleVaultFactory} from "src/pendle/PendleVaultFactory.sol";

interface PendleStrategy {
    function setVaultGaugeFactory(address _vaultGaugeFactory) external;
    function vaultGaugeFactory() external returns (address);
}

contract DeployYearnStrategy is Script, Test {
    PendleVaultFactory public factory;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        factory = new PendleVaultFactory(PENDLE.STRATEGY, DAO.STRATEGY_SDT_DISTRIBUTOR);

        PendleStrategy(PENDLE.STRATEGY).setVaultGaugeFactory(address(factory));

        // Check values 
        require(factory.strategy() == PENDLE.STRATEGY, "Strategy mismatch");
        require(factory.sdtDistributor() == DAO.STRATEGY_SDT_DISTRIBUTOR, "SDT Distributor mismatch");
        require(PendleStrategy(PENDLE.STRATEGY).vaultGaugeFactory() == address(factory), "Vault Gauge Factory mismatch");
        require(factory.vaultImpl() == 0x44A6A278A9a55fF22Fd5F7c6fe84af916396470C, "Vault Implementation mismatch");
        require(factory.CLAIM_REWARDS() == 0x633120100e108F03aCe79d6C78Aac9a56db1be0F, "Claim Rewards mismatch");
        require(factory.GAUGE_IMPL() == 0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9, "Gauge Implementation mismatch");
        require(factory.PENDLE_MARKET_FACTORY_V3() == 0x1A6fCc85557BC4fB7B534ed835a03EF056552D52, "Pendle Market Factory V3 mismatch");
        require(factory.GOVERNANCE() == DAO.GOVERNANCE, "Governance mismatch");
        require(factory.PENDLE_TOKEN() == PENDLE.TOKEN, "Pendle Token mismatch");
        require(factory.VESDT() == DAO.VESDT, "VESDT mismatch");
        require(factory.SDT() == DAO.SDT, "SDT mismatch");
        require(factory.VEBOOST() == 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506, "VEBOOST mismatch");

        vm.stopBroadcast();
    }
}
