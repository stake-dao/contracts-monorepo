// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";

import "address-book/src/dao/42161.sol";
import "address-book/src/lockers/42161.sol";

import "src/arbitrum/cake/IFO.sol";
import "src/arbitrum/cake/IFOHelper.sol";

contract IFOHelperTest is Test {
    IFO public ifo = IFO(0x34d774B06d45bd3db9D51724Fc98Dc097A58eF27);
    IFOHelper public ifoHelper;

    address ifoAdmin = 0x444D73Ea7bC7C72Ea11638203846dAD632677180;

    uint256 public constant BLOCK_NUMBER = 257216016;
    address public constant LOCKER = 0x1E6F87A9ddF744aF31157d8DaA1e3025648d042d;
    address public constant CAKE_IFO = 0xa6f907493269BEF3383fF0CBFd25e1Cc35167c3B;

    address public constant USER = address(0xb24B5d309a1A64135770A954496b3c408c558806);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"), BLOCK_NUMBER);

        ifoHelper = new IFOHelper(address(ifo), CAKE.EXECUTOR);

        vm.prank(DAO.GOVERNANCE);
        IExecutor(CAKE.EXECUTOR).allowAddress(address(ifoHelper));
    }

    function test_claim_and_release() public {
        ERC20 rewardToken = ifoHelper.rewardToken();
        bytes32 vestingScheduleId =
            ICakeIFOV8(CAKE_IFO).computeVestingScheduleIdForAddressAndPid(address(CAKE.EXECUTOR), 1);
        ifoHelper.release(1, vestingScheduleId);

        skip(100);

        vm.expectRevert(IFOHelper.NoDeposit.selector);
        ifoHelper.claim(1, vestingScheduleId);
        assertEq(rewardToken.balanceOf(address(this)), 0);

        skip(100);
        assertEq(rewardToken.balanceOf(USER), 0);

        vm.prank(USER);
        ifoHelper.claim(1, vestingScheduleId);
        assertGt(rewardToken.balanceOf(USER), 0);
        assertEq(rewardToken.balanceOf(address(USER)), ifoHelper.rewardClaimed(USER, 1));

        vm.expectRevert(IFOHelper.Unauthorized.selector);
        ifoHelper.recover(address(rewardToken));

        uint256 balance = rewardToken.balanceOf(address(ifoHelper));

        vm.prank(CAKE.EXECUTOR);
        ifoHelper.recover(address(rewardToken));
        assertEq(rewardToken.balanceOf(address(ifoHelper)), 0);
        assertEq(rewardToken.balanceOf(CAKE.EXECUTOR), balance);
    }
}
