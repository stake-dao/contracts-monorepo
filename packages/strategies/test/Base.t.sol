// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/src/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";
import {MockHarvester} from "test/mocks/MockHarvester.sol";
import {MockAllocator} from "test/mocks/MockAllocator.sol";

import "src/Accountant.sol";

abstract contract BaseTest is Test {
    using Math for uint256;

    ERC20Mock public rewardToken;
    ERC20Mock public stakingToken;

    MockStrategy public strategy;
    MockRegistry public registry;
    MockHarvester public harvester;
    MockAllocator public allocator;

    Accountant public accountant;

    function setUp() public virtual {
        /// Setup the reward and staking tokens
        rewardToken = new ERC20Mock("Reward Token", "RT", 18);
        stakingToken = new ERC20Mock("Staking Token", "ST", 18);

        /// Setup the strategy, registry, allocator, and accountant
        strategy = new MockStrategy();
        registry = new MockRegistry();
        allocator = new MockAllocator();
        harvester = new MockHarvester(address(rewardToken));
        accountant = new Accountant(address(this), address(registry), address(rewardToken));

        /// Set the vault
        registry.setVault(address(this));
        registry.setHarvester(address(harvester));

        /// Label the contracts
        vm.label({account: address(strategy), newLabel: "Strategy"});
        vm.label({account: address(registry), newLabel: "Registry"});
        vm.label({account: address(allocator), newLabel: "Allocator"});
        vm.label({account: address(harvester), newLabel: "Harvester"});
        vm.label({account: address(accountant), newLabel: "Accountant"});
        vm.label({account: address(rewardToken), newLabel: "Reward Token"});
        vm.label({account: address(stakingToken), newLabel: "Staking Token"});
    }
}
