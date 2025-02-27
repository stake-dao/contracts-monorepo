// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/src/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {MockRegistry} from "test/mocks/MockRegistry.sol";
import {MockHarvester} from "test/mocks/MockHarvester.sol";
import {MockAllocator} from "test/mocks/MockAllocator.sol";

import "src/Accountant.sol";

struct DefaultValues {
    address owner;
    address registry;
    address rewardToken;
    bytes4 protocolId;
}

abstract contract BaseTest is Test {
    using Math for uint256;

    ERC20Mock internal rewardToken;
    ERC20Mock internal stakingToken;

    MockStrategy internal strategy;
    MockRegistry internal registry;
    MockHarvester internal harvester;
    MockAllocator internal allocator;
    Accountant internal accountant;

    address internal owner = address(this);
    address internal vault = makeAddr("vault");
    bytes4 internal protocolId = bytes4(bytes("fake_id"));

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        /// Setup the reward and staking tokens
        rewardToken = new ERC20Mock("Reward Token", "RT", 18);
        stakingToken = new ERC20Mock("Staking Token", "ST", 18);

        /// Setup the strategy, registry, allocator, and accountant
        strategy = new MockStrategy();
        registry = new MockRegistry();
        allocator = new MockAllocator();
        harvester = new MockHarvester(address(rewardToken));
        accountant = new Accountant(owner, address(registry), address(rewardToken), protocolId);

        /// Set the vault
        registry.setVault(vault);
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

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    //////////////////////////////////////////////////////////////////////////*/
    function _boundValidProtocolFee(uint256 newProtocolFee) internal view returns (uint256) {
        return bound(newProtocolFee, 1, accountant.MAX_FEE_PERCENT() - accountant.getHarvestFeePercent());
    }
}
