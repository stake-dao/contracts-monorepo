// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import {CakeIFOFactory} from "src/cake/ifo/CakeIFOFactory.sol";
import {CAKE} from "address-book/lockers/56.sol";
import {DAO} from "address-book/dao/56.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import "src/cakeInit/IFOInitializableV8.sol";

contract OfferingToken is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(msg.sender, 100000e18);
    }
}

contract DeployIFOTest is Script, Test {
    CakeIFOFactory private factory = CakeIFOFactory(0x16c4A40C57aF157B0acb42ab71b8788fc5F23741);
    IFOInitializableV8 private cakeIFO = IFOInitializableV8(0x5b098F362F09F65038aD12901Ea6d7D4cb33c396);
    OfferingToken private offeringToken = OfferingToken(0xc0b480fB94Daac36A99862baaE2D54dD97355967);

    address[] private addresses = new address[](6);

    uint256[] private startEndTs = [1717758000, 1717779600];
    uint8 maxPoolId = 1;
    uint256 pointT = 0;
    uint256 vestingStartTs = 1717783200;
    //uint256 maxBufferPerSecond = 604800;

    function run() public {
        vm.startBroadcast(DAO.MAIN_DEPLOYER);
        // it needs to be runned on bnb network
        require(block.chainid == 56, "Wrong network");

        // Deploy oToken
        //offeringToken = new OfferingToken("Offering Token", "OT");

        // addresses[0] = CAKE.TOKEN;
        // addresses[1] = address(0xc0b480fB94Daac36A99862baaE2D54dD97355967); // offering token
        // addresses[2] = 0xDf4dBf6536201370F95e06A0F8a7a70fE40E388a; // cake profile
        // addresses[3] = 0x3aa289c56Ba2dD7576B3aeA11ffecF827f22e98f; // icake
        // addresses[4] = DAO.MAIN_DEPLOYER;
        // addresses[5] = 0xDf7952B35f24aCF7fC0487D01c8d5690a60DBa07;
        // 0xDf7952B35f24aCF7fC0487D01c8d5690a60DBa07; // pancake bunny
        // Deploy cakeIFO
        //cakeIFO = new IFOInitializableV8(addresses, startEndTs, 604800, maxPoolId, pointT, vestingStartTs);

        // create pools
        // 100% vesting, 0 cliff, duration, sliceperiodPerSecond
        //IIFOV8.VestingConfig memory vConfigPool1 = IIFOV8.VestingConfig(100, 0, 3 days, 60);
        // 60%
        //IIFOV8.VestingConfig memory vConfigPool2 = IIFOV8.VestingConfig(60, 0, 3 days, 60);
        //IIFOV8.SaleType saleTypePool1 = IIFOV8.SaleType(0);
        // 10K offering token, 10K lp token, 0 lp limit, no tax, 0% flax tax rate, pid 0,
        //cakeIFO.setPool(10000e18, 10000e18, 0, false, 0, 0, saleTypePool1, vConfigPool1);
        // 1000K CAKE per
        //cakeIFO.setPool(10000e18, 10000e18, 1000, false, 0, 0, saleTypePool1, vConfigPool2);
        // IIFOV8.VestingConfig memory vConfigPool2 = IIFOV8.VestingConfig(60, 0, 1 weeks, 10);
        // IIFOV8.SaleType saleTypePool2 = IIFOV8.SaleType(0);
        //cakeIFO.setPool(10000e18, 10000e18, 0, false, 0, 1, saleTypePool1, vConfigPool1);
        //offeringToken.transfer(address(cakeIFO), 20000e18);

        // set feeReceiver as governance at deploy time
        //abi.en
        //emit log_bytes(abi.encode(CAKE.LOCKER, CAKE.EXECUTOR, DAO.MAIN_DEPLOYER, DAO.GOVERNANCE));
        //factory = new CakeIFOFactory(CAKE.LOCKER, CAKE.EXECUTOR, DAO.MAIN_DEPLOYER, DAO.GOVERNANCE);
        //emit log_bytes(abi.encode(address(cakeIFO), CAKE.TOKEN, address(offeringToken), CAKE.LOCKER, CAKE.EXECUTOR, address(factory)));
        ///factory.setMerkleRoot(0xD3461552415dBD4887BBF1Ff9B4f3aC0331E4478, 0xaf233fb6a9641373981b810d0353a6340183efdb4593fb9663053cf317ad64ee, 1000e18);

        //factory.updateProtocolFee(1_500); // 15%
        //factory.setFeeReceiver(feeReceiver);

        vm.stopBroadcast();
    }
}
