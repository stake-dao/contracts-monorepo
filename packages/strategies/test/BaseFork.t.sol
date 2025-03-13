// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/src/Test.sol";

import {ILocker} from "@interfaces/stake-dao/ILocker.sol";

import {Allocator} from "src/Allocator.sol";
import {Accountant} from "src/Accountant.sol";
import {ProtocolController} from "src/ProtocolController.sol";

import {RewardVault} from "src/RewardVault.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";

/// TODO: Move to a helper package
import {Safe, Enum, SafeLibrary} from "test/utils/SafeLibrary.sol";

/// @title BaseTest
/// @notice Base test contract with common utilities and setup for all tests
abstract contract BaseForkTest is Test {
    address public immutable admin = address(this);
    address public immutable feeReceiver = makeAddr("Fee Receiver");

    bytes4 internal immutable protocolId;
    bool internal immutable harvested;
    address public immutable rewardToken;
    address public immutable stakingToken;

    address public immutable locker;

    Safe public gateway;
    Allocator public allocator;
    Accountant public accountant;
    ProtocolController public protocolController;

    address public strategy;

    RewardVault public rewardVault;
    RewardVault public rewardVaultImplementation;

    RewardReceiver public rewardReceiver;
    RewardReceiver public rewardReceiverImplementation;

    constructor(address _rewardToken, address _stakingToken, address _locker, bytes4 _protocolId, bool _harvested) {
        locker = _locker;
        protocolId = _protocolId;
        rewardToken = _rewardToken;
        stakingToken = _stakingToken;
        harvested = _harvested;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        /// 1. Deploy Protocol Controller.
        protocolController = new ProtocolController();

        /// 2. Deploy Accountant.
        accountant = new Accountant({
            _owner: admin,
            _registry: address(protocolController),
            _rewardToken: address(rewardToken),
            _protocolId: protocolId
        });

        /// 3. Deploy Reward Vault Implementation.
        rewardVaultImplementation = new RewardVault({
            protocolId: protocolId,
            protocolController: address(protocolController),
            accountant: address(accountant)
        });

        /// 4. Deploy Reward Receiver Implementation.
        rewardReceiverImplementation = new RewardReceiver();

        address[] memory owners = new address[](1);
        owners[0] = admin;

        /// 5. Deploy Gateway.
        gateway = SafeLibrary.deploySafe({_owners: owners, _threshold: 1, _saltNonce: uint256(uint32(protocolId))});

        /// 6. Setup contracts in protocol controller.
        protocolController.setFeeReceiver(protocolId, feeReceiver);

        /// 7. If Locker != 0, Gateway should be the governance of the locker.
        if (locker != address(0)) {
            address governance = ILocker(locker).governance();

            vm.prank(governance);
            ILocker(locker).setGovernance(address(gateway));
        }

        /// 8. Deploy Allocator.
        allocator = new Allocator(locker, address(gateway), harvested);

        /// 7. Setup contracts in protocol controller.
        protocolController.setAccountant(protocolId, address(accountant));
        protocolController.setAllocator(protocolId, address(allocator));

        /// 7. Label common contracts.
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
