// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "address-book/dao/1.sol";
import "utils/VyperDeployer.sol";
import "address-book/lockers/1.sol";
import "address-book/protocols/1.sol";

import {Constants} from "src/base/utils/Constants.sol";
import {PendleVaultFactory} from "src/pendle/PendleVaultFactory.sol";
import {ILiquidityGaugeStrat} from "src/base/interfaces/ILiquidityGaugeStrat.sol";

interface PendleStrategy {
    function setVaultGaugeFactory(address _vaultGaugeFactory) external;
    function vaultGaugeFactory() external returns (address);
}

contract DeployPendleVaultFactory is Script, Test {
    PendleVaultFactory public factory;

    VyperDeployer public vyperDeployer = new VyperDeployer();

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);

        // Deploy LGV4Strat impl
        ILiquidityGaugeStrat gaugeImpl = ILiquidityGaugeStrat(deployBytecode(Constants.LGV4_STRAT_BYTECODE, ""));

        factory = new PendleVaultFactory(PENDLE.STRATEGY, DAO.STRATEGY_SDT_DISTRIBUTOR, address(gaugeImpl));

        //PendleStrategy(PENDLE.STRATEGY).setVaultGaugeFactory(address(factory));

        // Check values
        require(factory.strategy() == PENDLE.STRATEGY, "Strategy mismatch");
        require(factory.sdtDistributor() == DAO.STRATEGY_SDT_DISTRIBUTOR, "SDT Distributor mismatch");
        //require(PendleStrategy(PENDLE.STRATEGY).vaultGaugeFactory() == address(factory), "Vault Gauge Factory mismatch");
        require(factory.vaultImpl() == 0x44A6A278A9a55fF22Fd5F7c6fe84af916396470C, "Vault Implementation mismatch");
        require(factory.CLAIM_REWARDS() == 0x633120100e108F03aCe79d6C78Aac9a56db1be0F, "Claim Rewards mismatch");
        require(factory.gaugeImpl() == address(gaugeImpl), "Gauge Implementation mismatch");
        require(
            factory.PENDLE_MARKET_FACTORY_V3() == 0x1A6fCc85557BC4fB7B534ed835a03EF056552D52,
            "Pendle Market Factory V3 mismatch"
        );
        require(factory.GOVERNANCE() == DAO.GOVERNANCE, "Governance mismatch");
        require(factory.PENDLE() == PENDLE.TOKEN, "Pendle Token mismatch");
        require(factory.VESDT() == DAO.VESDT, "VESDT mismatch");
        require(factory.SDT() == DAO.SDT, "SDT mismatch");
        require(factory.VEBOOST() == 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506, "VEBOOST mismatch");

        // Deploy vault for eEth
        /*
        vm.recordLogs();
        factory.cloneAndInit(0xF32e58F92e60f4b0A37A69b95d642A471365EAe8);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        (address vault,,) = abi.decode(entries[0].data, (address, address, address));
        (address gaugeProxy,,) = abi.decode(entries[2].data, (address, address, address));

        console.log("Vault deployed at: ", vault);
        console.log("Gauge deployed at: ", gaugeProxy);
        */

        vm.stopBroadcast();
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) internal returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }

}
