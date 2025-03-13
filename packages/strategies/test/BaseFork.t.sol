// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/src/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Accountant} from "src/Accountant.sol";
import {ProtocolController} from "src/ProtocolController.sol";

import {RewardVault} from "src/RewardVault.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";

/// TODO: Move to a helper package
import {SafeLibrary} from "test/utils/SafeLibrary.sol";

/// @title BaseTest
/// @notice Base test contract with common utilities and setup for all tests
abstract contract BaseTest is Test {
    using Math for uint256;

    address public immutable admin = address(this);

    bytes4 internal immutable protocolId;

    address public immutable rewardToken;
    address public immutable stakingToken;

    address public immutable locker;

    address public gateway;
    address public protocolController;

    address public allocator;
    address public accountant;
    address public strategy;

    address public rewardVault;
    address public rewardVaultImplementation;

    address public rewardReceiver;
    address public rewardReceiverImplementation;

    constructor(address _rewardToken, address _stakingToken, address _locker, bytes4 _protocolId) {
        locker = _locker;
        protocolId = _protocolId;
        rewardToken = _rewardToken;
        stakingToken = _stakingToken;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        /// 1. Deploy Protocol Controller.
        protocolController = address(new ProtocolController());

        /// 2. Deploy Accountant.
        accountant = address(
            new Accountant({
                _owner: admin,
                _registry: address(protocolController),
                _rewardToken: address(rewardToken),
                _protocolId: protocolId
            })
        );

        /// 3. Deploy Reward Vault Implementation.
        rewardVaultImplementation = address(
            new RewardVault({protocolId: protocolId, protocolController: protocolController, accountant: accountant})
        );

        /// 4. Deploy Reward Receiver Implementation.
        rewardReceiverImplementation = address(new RewardReceiver());

        address[] memory owners = new address[](1);
        owners[0] = admin;

        /// 5. Deploy Gateway
        gateway = SafeLibrary.deploySafe({_owners: owners, _threshold: 1, _saltNonce: uint256(uint32(protocolId))});

        /// Label common contracts
        vm.label({account: address(locker), newLabel: "Locker"});
        vm.label({account: address(gateway), newLabel: "Gateway"});
        vm.label({account: address(strategy), newLabel: "Strategy"});
        vm.label({account: address(allocator), newLabel: "Allocator"});
        vm.label({account: address(accountant), newLabel: "Accountant"});
        vm.label({account: address(rewardVault), newLabel: "Reward Vault"});
        vm.label({account: address(rewardToken), newLabel: "Reward Token"});
        vm.label({account: address(stakingToken), newLabel: "Staking Token"});
        vm.label({account: address(rewardReceiver), newLabel: "Reward Receiver"});
        vm.label({account: address(protocolController), newLabel: "Protocol Controller"});
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    //////////////////////////////////////////////////////////////////////////*/
    /// @notice Utility function to ensure a fuzzed address has not been previously labeled
    function _assumeUnlabeledAddress(address fuzzedAddress) internal view {
        vm.assume(bytes10(bytes(vm.getLabel(fuzzedAddress))) == bytes10(bytes("unlabeled:")));
    }

    /// @notice Helper to deploy code to a specific address (for harness contracts)
    function _deployHarnessCode(string memory artifactPath, bytes memory constructorArgs, address target) internal {
        deployCodeTo(artifactPath, constructorArgs, target);
    }
}
