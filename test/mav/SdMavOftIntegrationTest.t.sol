// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import "src/mav/depositor/MAVDepositor.sol";

import {sdMAV} from "src/mav/token/sdMAV.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ILocker} from "src/base/interfaces/ILocker.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SdMavOftIntegrationTest is Test {
    VyperDeployer vyperDeployer = new VyperDeployer();
    sdMAV public sdMav;
    MAVDepositor public depositor;
    ILiquidityGauge internal liquidityGauge;
    ILocker internal locker = ILocker(0xdBD6170396ECE3DCd51195950A2dF7F7635F9e38);
    address public lzEndpoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
    address public constant MAV = AddressBook.MAV;

    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public mavHolder = 0xb229fF45b62b3A01918893C34349cA8aC0f0A576;

    function setUp() public virtual {
        sdMav = new sdMAV("Stake DAO MAV", "sdMAV", lzEndpoint);

        address liquidityGaugeImpl = vyperDeployer.deployContract("src/base/staking/LiquidityGaugeV4.vy");

        // Deploy LiquidityGauge
        liquidityGauge = ILiquidityGauge(
            address(
                new TransparentUpgradeableProxy(
                liquidityGaugeImpl,
                AddressBook.PROXY_ADMIN,
                abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(sdMav),
                address(this),
                AddressBook.SDT,
                AddressBook.VE_SDT,
                AddressBook.VE_SDT_BOOST_PROXY,
                AddressBook.SDT_DISTRIBUTOR
                )
                )
            )
        );

        depositor = new MAVDepositor(MAV, address(locker), address(sdMav), address(liquidityGauge));
        vm.prank(locker.governance());
        locker.setDepositor(address(depositor));
    }

    function testMigration() external {
        // Mint sdMavOft token by governance
        assertEq(sdMav.totalSupply(), 0);
        uint256 amountToMint = 30_000e18;
        sdMav.mint(address(this), amountToMint);
        assertEq(sdMav.totalSupply(), amountToMint);
        assertEq(sdMav.balanceOf(address(this)), amountToMint);

        // deposit the whole amount into the depositor to obtain sdMAV-gauge token
        sdMav.approve(address(liquidityGauge), amountToMint);
        liquidityGauge.deposit(amountToMint, address(this));

        // transfer gauge token to a recipient
        IERC20(address(liquidityGauge)).transfer(deployer, amountToMint);

        // set the depositor as token operator
        sdMav.setOperator(address(depositor));

        // deposit token
        vm.startPrank(mavHolder);
        uint256 amountToDeposit = 1000e18;
        IERC20(MAV).approve(address(depositor), amountToDeposit);
        depositor.deposit(amountToDeposit, true, true, mavHolder);

        uint256 gaugeBalance = liquidityGauge.totalSupply();
        assertEq(gaugeBalance, amountToMint + amountToDeposit);
    }
}
