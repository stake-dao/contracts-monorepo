// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "src/fx/locker/FXNLocker.sol";
import "src/fx/depositor/FXNDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployVeCRVLocker is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address public liquidityGaugeImpl = 0x93c951D3281Cc79e9FE1B1C87e50693D202F4C17;

    IERC20 private token;
    FXNLocker private locker;
    IVeToken private veToken;

    sdToken internal _sdToken;
    FXNDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    function run() public {
        vm.startBroadcast(deployer);

        token = IERC20(AddressBook.FXN);
        veToken = IVeToken(AddressBook.VE_FXN);
        _sdToken = new sdToken("Stake DAO FXN", "sdFXN");

        // Deploy LiquidityGauge
        liquidityGauge = ILiquidityGauge(
            address(
                new TransparentUpgradeableProxy(
                liquidityGaugeImpl,
                AddressBook.PROXY_ADMIN,
                abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(_sdToken),
                address(deployer),
                AddressBook.SDT,
                AddressBook.VE_SDT,
                AddressBook.VE_SDT_BOOST_PROXY,
                AddressBook.SDT_DISTRIBUTOR
                )
                )
            )
        );

        /// Salt for CREATE2
        bytes32 salt = bytes32(uint256(uint160(address(token))) << 96);
        locker = new FXNLocker{salt: salt}(deployer, address(token), address(veToken));
        depositor = new FXNDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge));

        _sdToken.setOperator(address(depositor));
        locker.setDepositor(address(depositor));

        locker.transferGovernance(governance);
        depositor.transferGovernance(governance);

        if (locker.token() != address(token)) revert();
        if (locker.veToken() != address(veToken)) revert();
        if (locker.depositor() != address(depositor)) revert();
        if (locker.governance() != address(deployer)) revert();
        if (locker.futureGovernance() != governance) revert();

        if (depositor.token() != address(token)) revert();
        if (depositor.locker() != address(locker)) revert();
        if (depositor.minter() != address(_sdToken)) revert();
        if (depositor.governance() != address(deployer)) revert();
        if (depositor.futureGovernance() != governance) revert();
        if (depositor.gauge() != address(liquidityGauge)) revert();

        vm.stopBroadcast();
    }
}
