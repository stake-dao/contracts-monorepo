// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {AddressBook} from "@addressBook/AddressBook.sol";
import {CAKEDepositor} from "src/cake/depositor/CAKEDepositor.sol";
import {CakeLocker} from "src/cake/locker/CakeLocker.sol";
import {sdToken} from "src/base/token/sdToken.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {VyperDeployer} from "utils/VyperDeployer.sol";

contract DeployCakeLL is Script, Test {
    sdToken internal _sdToken;
    ILiquidityGauge internal liquidityGauge;
    CAKEDepositor private depositor;
    CakeLocker private locker;

    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant VE_CAKE = 0x5692DB8177a81A6c6afc8084C2976C9933EC1bAB;
    address public constant GOV = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;
    address public DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    VyperDeployer vyperDeployer = new VyperDeployer();

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("bnb"));
        vm.selectFork(forkId);
    }

    function run() public {
        vm.startBroadcast();

        // Deploy sdCAKE
        _sdToken = new sdToken("Stake DAO CAKE", "sdCAKE");

        bytes memory constructorParams = abi.encode(address(_sdToken), GOV);
        liquidityGauge = ILiquidityGauge(
            vyperDeployer.deployContract("src/base/staking/LiquidityGaugeV4XChain.vy", constructorParams)
        );

        // Deploy CAKE Locker
        locker = new CakeLocker(DEPLOYER, CAKE, VE_CAKE);

        // Deploy CAKE Depositor
        depositor = new CAKEDepositor(CAKE, address(locker), address(_sdToken), address(liquidityGauge));

        // Setters
        locker.setDepositor(address(depositor));
        _sdToken.setOperator(address(depositor));

        // Transfer ownership
        locker.transferGovernance(GOV);
        depositor.transferGovernance(GOV);

        vm.stopBroadcast();
    }
}