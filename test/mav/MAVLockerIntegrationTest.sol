// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "utils/VyperDeployer.sol";

import "src/mav/locker/MAVLocker.sol";
import "src/mav/depositor/MAVDepositor.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";

import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MAVLockerIntegrationTest is Test {
    VyperDeployer vyperDeployer = new VyperDeployer();

    uint256 private constant MIN_LOCK_DURATION = 1 weeks;
    uint256 private constant MAX_LOCK_DURATION = 4 * 365 days;

    IERC20 private token;
    MAVLocker private locker;
    IVotingEscrowMav private veToken;

    sdToken internal _sdToken;
    MAVDepositor private depositor;
    ILiquidityGauge internal liquidityGauge;

    function setUp() public virtual {
        token = IERC20(AddressBook.MAV);
        veToken = IVotingEscrowMav(AddressBook.VE_MAV);
        _sdToken = new sdToken("Stake DAO MAV", "sdMAV");

        address liquidityGaugeImpl = vyperDeployer.deployContract("src/base/staking/LiquidityGaugeV4.vy");

        // Deploy LiquidityGauge
        liquidityGauge = ILiquidityGauge(
            address(
                new TransparentUpgradeableProxy(
                liquidityGaugeImpl,
                AddressBook.PROXY_ADMIN,
                abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(_sdToken),
                address(this),
                AddressBook.SDT,
                AddressBook.VE_SDT,
                AddressBook.VE_SDT_BOOST_PROXY,
                AddressBook.SDT_DISTRIBUTOR
                )
                )
            )
        );

        locker = new MAVLocker(address(this), address(token), address(veToken));
        depositor = new MAVDepositor(address(token), address(locker), address(_sdToken), address(liquidityGauge));

        locker.setDepositor(address(depositor));
        _sdToken.setOperator(address(depositor));

        // Mint MAV to the MAVLocker contract
        deal(address(token), address(locker), 100e18);

        locker.createLock(100e18, MAX_LOCK_DURATION);
    }

    function test_initialization() public {
        assertEq(locker.token(), address(token));
        assertEq(locker.veToken(), address(veToken));
        assertEq(locker.depositor(), address(depositor));

        assertEq(depositor.minter(), address(_sdToken));
        assertEq(depositor.gauge(), address(liquidityGauge));
    }
}
