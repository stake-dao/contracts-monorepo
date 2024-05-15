// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "address-book/dao/1.sol";
import "address-book/lockers/1.sol";

import "src/base/depositor/DepositorV4.sol";
import "src/yearn/depositor/YFIDepositorHelper.sol";
import {IYearnVestingFactory} from "src/base/interfaces/IYearnVestingFactory.sol";

contract YFIDepositorHelperIntegrationTest is Test {
    using SafeERC20 for IERC20;

    address a = address(0xbaba);
    IYearnVestingFactory YearnFactory = IYearnVestingFactory(0x850De8D7d65A7b7D5bc825ba29543f41B8E8aFd2);
    YFIDepositorHelper depositorHelper;

    function setUp() public virtual {
        vm.createSelectFork("mainnet");
        depositorHelper = new YFIDepositorHelper(YFI.DEPOSITOR, YFI.TOKEN);
    }

    function test_deposit_yearn_helper() public {
        uint256 lockIncentive = YFIDepositor(YFI.DEPOSITOR).incentiveToken();
        vm.startPrank(YearnFactory.OWNER());
        IERC20(YFI.TOKEN).approve(address(YearnFactory), 20 ether);
        uint256 idx = YearnFactory.create_vest(a, 20 ether, 60 * 60 * 24);
        YearnFactory.set_liquid_locker(YFI.GAUGE, address(depositorHelper));
        vm.stopPrank();

        vm.prank(a);
        (address vesting, uint256 vestedAmount) = YearnFactory.deploy_vesting_contract(idx, YFI.GAUGE, 20 ether);

        assertEq(IERC20(YFI.GAUGE).balanceOf(vesting), vestedAmount);
        assertEq(IERC20(YFI.GAUGE).balanceOf(vesting), 20 ether + lockIncentive);
    }
}
