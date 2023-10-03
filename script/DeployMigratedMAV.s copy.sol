// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "src/mav/locker/MAVLocker.sol";
import "src/mav/depositor/MAVDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployMigratedMAV is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public governance = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    address public liquidityGaugeImpl = 0x93c951D3281Cc79e9FE1B1C87e50693D202F4C17;
    address public claimer = 0x633120100e108F03aCe79d6C78Aac9a56db1be0F;

    IERC20 private token;
    IVotingEscrowMav private veToken;

    sdToken internal _sdToken;
    MAVLocker internal locker;
    MAVDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    function run() public {
        vm.startBroadcast(deployer);

        token = IERC20(AddressBook.MAV);
        veToken = IVotingEscrowMav(AddressBook.VE_MAV);

        locker = MAVLocker(payable(0xdBD6170396ECE3DCd51195950A2dF7F7635F9e38));
        _sdToken = sdToken(payable(0x50687515e93C43964733282F9DB8683F80BB02f9));

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

        liquidityGauge.set_claimer(claimer);

        depositor = new MAVDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge));
        locker.setDepositor(address(depositor));

        /// Transfer Governance
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
