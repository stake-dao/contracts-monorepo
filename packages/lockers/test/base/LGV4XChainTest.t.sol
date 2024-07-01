// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Vm.sol";
import "forge-std/src/Test.sol";

import "address-book/src/dao/1.sol";
import "address-book/src/lockers/1.sol";
import "address-book/src/protocols/1.sol";

import {Constants} from "src/base/utils/Constants.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

contract LGV4XChainTest is Test {
    address public stakeToken;
    address public rewardToken;

    address public staker1 = vm.addr(1);
    address public staker2 = vm.addr(2);
    address public staker3 = vm.addr(3);
    address public rewardDistributor = vm.addr(4);
    address public claimer = vm.addr(5);

    ILiquidityGauge public liquidityGauge;

    uint256 amountToNotify = 100e18;
    uint256 amountToDeposit = 50e18;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        stakeToken = CRV.SDTOKEN;
        rewardToken = DAO.SDT;

        bytes memory constructorParams = abi.encode(stakeToken, address(this));

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        deployedAddress = deployBytecode(Constants.LGV4_XCHAIN_BYTECODE, constructorParams);

        liquidityGauge = ILiquidityGauge(deployedAddress);

        // add reward token
        liquidityGauge.add_reward(DAO.SDT, rewardDistributor);

        // set claimer
        liquidityGauge.set_claimer(claimer);

        deal(stakeToken, staker1, amountToDeposit);
        deal(stakeToken, staker2, amountToDeposit);
        deal(rewardToken, rewardDistributor, amountToNotify);

        // Notify the weekly reward
        vm.startPrank(rewardDistributor);
        ERC20(rewardToken).approve(address(liquidityGauge), amountToNotify);
        liquidityGauge.deposit_reward_token(rewardToken, amountToNotify);
        vm.stopPrank();
    }

    function testDepositAndWithdrawWithoutRewards() external {
        // Staker1 deposits for staker1
        vm.startPrank(staker1);
        ERC20(stakeToken).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker1);
        assertEq(ERC20(stakeToken).balanceOf(staker1), 0);
        assertEq(liquidityGauge.balanceOf(staker1), amountToDeposit);
        vm.stopPrank();

        // Staker 2 deposits for staker3
        vm.startPrank(staker2);
        ERC20(stakeToken).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker3);
        assertEq(ERC20(stakeToken).balanceOf(staker2), 0);
        assertEq(liquidityGauge.balanceOf(staker2), 0);
        assertEq(liquidityGauge.balanceOf(staker3), amountToDeposit);
        vm.stopPrank();

        skip(5 seconds);

        // Staker1 withdraw all
        vm.prank(staker1);

        liquidityGauge.withdraw(amountToDeposit, false);
        assertEq(ERC20(stakeToken).balanceOf(staker1), amountToDeposit);
        assertEq(liquidityGauge.balanceOf(staker1), 0);

        // expect revert when staker2 try to withdraw
        vm.prank(staker2);
        vm.expectRevert();
        liquidityGauge.withdraw(amountToDeposit, false);

        // Staker3 withdraw all
        vm.prank(staker3);
        liquidityGauge.withdraw(amountToDeposit, false);
        assertEq(ERC20(stakeToken).balanceOf(staker3), amountToDeposit);
        assertEq(liquidityGauge.balanceOf(staker3), 0);
    }

    function testClaimReward() external {
        // Staker1 deposits for staker1
        vm.startPrank(staker1);
        ERC20(stakeToken).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker1);
        vm.stopPrank();

        skip(8 days);

        assertEq(ERC20(rewardToken).balanceOf(staker1), 0);
        uint256 claimableReward = liquidityGauge.claimable_reward(staker1, rewardToken);

        vm.prank(staker1);
        liquidityGauge.claim_rewards(staker1);

        uint256 claimedReward = liquidityGauge.claimed_reward(staker1, rewardToken);
        uint256 rewardClaimed = ERC20(rewardToken).balanceOf(staker1);

        assertApproxEqRel(rewardClaimed, amountToNotify, 0.5e18);
        assertEq(claimableReward, rewardClaimed);
        assertEq(claimedReward, rewardClaimed);
    }

    function testClaimRewardsForOthers() external {
        // Staker1 deposits for staker1
        vm.startPrank(staker1);
        ERC20(stakeToken).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker1);
        vm.stopPrank();

        skip(8 days);

        vm.prank(staker2);
        // the reward can be riderect to staker2 only
        // if the msg.sender is the staker1
        vm.expectRevert();
        liquidityGauge.claim_rewards(staker1, staker2);

        assertEq(ERC20(rewardToken).balanceOf(staker1), 0);
        assertEq(ERC20(rewardToken).balanceOf(staker2), 0);
        vm.prank(staker1);
        liquidityGauge.claim_rewards(staker1, staker2);
        assertEq(ERC20(rewardToken).balanceOf(staker1), 0);
        assertGt(ERC20(rewardToken).balanceOf(staker2), 0);
    }

    function testClaimRewardWithRewardReceiverSet() external {
        // set staker2 as reward receiver for staker1
        vm.prank(staker1);
        liquidityGauge.set_rewards_receiver(staker2);

        // Staker1 deposits for staker1
        vm.startPrank(staker1);
        ERC20(stakeToken).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker1);
        vm.stopPrank();

        skip(8 days);

        uint256 expectedReward = liquidityGauge.claimable_reward(staker1, rewardToken);

        // reward will be send to staker2
        assertEq(ERC20(rewardToken).balanceOf(staker2), 0);
        liquidityGauge.claim_rewards(staker1);
        assertGt(ERC20(rewardToken).balanceOf(staker2), 0);
        assertEq(ERC20(rewardToken).balanceOf(staker2), expectedReward);
    }

    function testClaimRewardsFor() external {
        // Staker1 deposits for staker1
        vm.startPrank(staker1);
        ERC20(stakeToken).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker1);
        vm.stopPrank();

        vm.expectRevert();
        // only the claimer can do that
        liquidityGauge.claim_rewards_for(staker1, staker1);
        vm.prank(claimer);
        liquidityGauge.claim_rewards_for(staker1, staker1);
    }

    function testClaimRewardAfterTransferGaugeToken() external {
        // Staker1 deposits for staker1
        vm.startPrank(staker1);
        ERC20(stakeToken).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker1);

        skip(8 days);

        ERC20(address(liquidityGauge)).transfer(staker2, liquidityGauge.balanceOf(staker1));

        skip(1 days);

        vm.stopPrank();

        assertEq(ERC20(rewardToken).balanceOf(staker1), 0);
        assertEq(ERC20(rewardToken).balanceOf(staker2), 0);
        vm.prank(staker1);
        liquidityGauge.claim_rewards();
        vm.prank(staker2);
        liquidityGauge.claim_rewards();
        assertGt(ERC20(rewardToken).balanceOf(staker1), 0);
        assertEq(ERC20(rewardToken).balanceOf(staker2), 0);
    }

    function testTransferGovernance() external {
        liquidityGauge.commit_transfer_ownership(staker1);
        assertEq(liquidityGauge.admin(), address(this));
        assertEq(liquidityGauge.future_admin(), staker1);
        vm.prank(staker1);
        liquidityGauge.accept_transfer_ownership();
        assertEq(liquidityGauge.admin(), staker1);
    }

    function deployBytecode(bytes memory bytecode, bytes memory args) private returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }
}
