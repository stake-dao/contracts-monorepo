// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";

import {Constants} from "src/base/utils/Constants.sol";

import {sdToken} from "src/base/token/sdToken.sol";
import {AddressBook} from "@addressBook/AddressBook.sol";
import {ILiquidityGauge} from "src/base/interfaces/ILiquidityGauge.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

contract LGV4XChainTest is Test {

    address public sdCrv;
    address public rewardToken;

    address public staker1 = vm.addr(1);
    address public staker2 = vm.addr(2);
    address public staker3 = vm.addr(3);
    address public rewardDistributor = vm.addr(4);
    address public claimer = vm.addr(5);

    ILiquidityGauge public liquidityGauge;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        sdCrv = AddressBook.SD_CRV;
        rewardToken = AddressBook.SDT;

        bytes memory constructorParams = abi.encode(sdCrv, address(this));

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        deployedAddress = deployBytecode(Constants.LGV4_XCHAIN_BYTECODE, constructorParams);

        liquidityGauge = ILiquidityGauge(deployedAddress);

        // add reward token
        liquidityGauge.add_reward(AddressBook.SDT, rewardDistributor);

        // set claimer
        liquidityGauge.set_claimer(claimer);

        deal(sdCrv, staker1, 100e18);
        deal(sdCrv, staker2, 100e18);
        deal(rewardToken, rewardDistributor, 100e18);

    }

    function deployBytecode(bytes memory bytecode, bytes memory args) private returns (address deployed) {
        bytecode = abi.encodePacked(bytecode, args);

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployed != address(0), "DEPLOYMENT_FAILED");
    }

    function testDepositAndWithdrawWithoutRewards() external {
        uint256 amountToDeposit = 50e18;

        // Staker1 deposits for staker1
        vm.startPrank(staker1);
        ERC20(sdCrv).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker1);
        vm.stopPrank();

        // Staker 2 deposits for staker3
        vm.startPrank(staker2);
        ERC20(sdCrv).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker3);
        vm.stopPrank();

        skip(5 seconds);

        // Staker1 withdraw all
        vm.prank(staker1);
        liquidityGauge.withdraw(amountToDeposit, false);

        // expect revert when staker2 try to withdraw
        vm.prank(staker2);
        vm.expectRevert();
        liquidityGauge.withdraw(amountToDeposit, false);

        // Staker3 withdraw all
        vm.prank(staker3);
        liquidityGauge.withdraw(amountToDeposit, false);
    }

    function testClaimReward() external {
        uint256 amountToDeposit = 50e18;
        uint256 amountToNotify = 100e18;

        // Staker1 deposits for staker1
        vm.startPrank(staker1);
        ERC20(sdCrv).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker1);
        vm.stopPrank();

        // Add reward token as reward
        vm.startPrank(rewardDistributor);
        ERC20(rewardToken).approve(address(liquidityGauge), amountToNotify);
        liquidityGauge.deposit_reward_token(rewardToken, amountToNotify);
        vm.stopPrank();

        skip(8 days);

        assertEq(ERC20(rewardToken).balanceOf(staker1), 0);
        vm.startPrank(staker1);
        liquidityGauge.claim_rewards(staker1);
        uint256 rewardClaimed = ERC20(rewardToken).balanceOf(staker1);
        assertApproxEqRel(rewardClaimed, amountToNotify, 0.5e18);
        emit log_uint(rewardClaimed);
    }

    function testClaimRewardsFor() external {
        uint256 amountToDeposit = 50e18;

        // Staker1 deposits for staker1
        vm.startPrank(staker1);
        ERC20(sdCrv).approve(address(liquidityGauge), amountToDeposit);
        liquidityGauge.deposit(amountToDeposit, staker1);
        vm.stopPrank();

        vm.expectRevert();
        // only the claimer can do that
        liquidityGauge.claim_rewards_for(staker1, staker1);
        vm.prank(claimer);
        liquidityGauge.claim_rewards_for(staker1, staker1);
    }

    function testTransferGovernance() external {
        liquidityGauge.commit_transfer_ownership(staker1);
        assertEq(liquidityGauge.admin(), address(this));
        assertEq(liquidityGauge.future_admin(), staker1);
        vm.prank(staker1);
        liquidityGauge.accept_transfer_ownership();
        assertEq(liquidityGauge.admin(), staker1);
    }
}