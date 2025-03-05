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

        // Mock the registry `assets` function used to fetch the vault's asset to always return the staking token in our tests
        // `clearMockedCalls` can be used to clear the mocked calls in a specific test (https://book.getfoundry.sh/cheatcodes/clear-mocked-calls)
        bytes[] memory mocks = new bytes[](1);
        mocks[0] = abi.encode(address(rewardToken));
        vm.mockCalls(address(registry), abi.encodeWithSelector(MockRegistry.asset.selector), mocks);

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
    function _boundValidProtocolFee(uint128 newProtocolFee) internal view returns (uint128) {
        return
            uint128(bound(uint256(newProtocolFee), 1, accountant.MAX_FEE_PERCENT() - accountant.getHarvestFeePercent()));
    }

    /// @notice Utility function to ensure a fuzzed address has not been previously labeled
    ///         Sometimes it is useful to ask the fuzzer engineer to use an address that is not already
    ///         flagged as important in our system. This is what this function does.
    ///         The Foundry function `getLabel` retrieves the label for an address if it was previously
    ///         labeled. If not, it returns the address prefixed with `unlabeled:`. The function asks the fuzzer
    ///         to redraw a value until the function getLabel returns a value with the unlabeled prefix.
    function _assumeUnlabeledAddress(address fuzzedAddress) internal view {
        vm.assume(bytes10(bytes(vm.getLabel(fuzzedAddress))) == bytes10(bytes("unlabeled:")));
    }

    /// @notice This modifier can be used to replace the Accountant contract with the AccountantHarness contract.
    ///         The AccountantHarness contract surcharges the Accountant contract with additional helpers/setters
    ///         that must only be used for **testing purposes**. It allows testing contract functions in isolation
    ///         and/or reading internal data not intended to be exposed natively.
    ///         Only the runtime code stored for the Accountant contract is replaced with AccountantHarness's code.
    ///         The storage stays the same, every variables stored at Accountant's construction time will be usable
    ///         by the AccountantHarness implementation.
    modifier _cheat_replaceAccountantWithAccountantHarness() {
        deployCodeTo(
            "out/AccountantHarness.t.sol/AccountantHarness.json",
            abi.encode(owner, address(registry), address(rewardToken), protocolId),
            address(accountant)
        );

        // the code of AccountantHarness is now stored at address(accountant)

        _;
    }
}
