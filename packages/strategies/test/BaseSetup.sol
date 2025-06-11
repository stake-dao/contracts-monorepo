// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ILocker} from "@interfaces/stake-dao/ILocker.sol";
import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import "forge-std/src/Test.sol";
import {Accountant} from "src/Accountant.sol";
import {Allocator} from "src/Allocator.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {RewardVault, IERC20, IStrategy} from "src/RewardVault.sol";
import {Safe, SafeLibrary} from "test/utils/SafeLibrary.sol";

/// @title BaseTest
/// @notice Base test contract with common utilities and setup for all tests
abstract contract BaseSetup is Test {
    address public immutable admin = address(this);
    address public immutable feeReceiver = makeAddr("Fee Receiver");

    bytes4 internal protocolId;
    address public rewardToken;
    IStrategy.HarvestPolicy internal harvestPolicy;

    address public locker;

    Safe public gateway;
    Allocator public allocator;
    Accountant public accountant;
    ProtocolController public protocolController;

    address public factory;
    address public strategy;

    RewardVault public rewardVaultImplementation;
    RewardReceiver public rewardReceiverImplementation;

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _beforeSetup(
        address _rewardToken,
        address _locker,
        bytes4 _protocolId,
        IStrategy.HarvestPolicy _harvestPolicy
    ) internal {
        /// 0. Initialize variables.
        locker = _locker;
        protocolId = _protocolId;
        rewardToken = _rewardToken;
        harvestPolicy = _harvestPolicy;

        /// 1. Deploy Protocol Controller.
        protocolController = new ProtocolController();

        /// 2. Set fee receiver.
        protocolController.setFeeReceiver(protocolId, feeReceiver);

        /// 3. Deploy Accountant.
        accountant = new Accountant({
            _owner: admin,
            _registry: address(protocolController),
            _rewardToken: address(rewardToken),
            _protocolId: protocolId
        });

        /// 4. Deploy Reward Vault Implementation.
        rewardVaultImplementation = new RewardVault({
            protocolId: protocolId,
            protocolController: address(protocolController),
            accountant: address(accountant),
            policy: harvestPolicy
        });

        /// 5. Deploy Reward Receiver Implementation.
        rewardReceiverImplementation = new RewardReceiver();

        address[] memory owners = new address[](1);
        owners[0] = admin;

        /// 6. Deploy Gateway.
        gateway = SafeLibrary.deploySafe({_owners: owners, _threshold: 1, _saltNonce: uint256(uint32(protocolId))});

        /// 8. Setup contracts in protocol controller.
        protocolController.setAccountant(protocolId, address(accountant));

        /// 9. If Locker != 0, Gateway should be the governance of the locker.
        if (locker != address(0)) {
            address governance = ILocker(locker).governance();

            vm.prank(governance);
            ILocker(locker).setGovernance(address(gateway));
        }

        /// 10. Deploy Allocator.
        allocator = new Allocator(locker, address(gateway));

        /// 11. Label common contracts.
        vm.label({account: address(locker), newLabel: "Locker"});
        vm.label({account: address(gateway), newLabel: "Gateway"});
        vm.label({account: address(strategy), newLabel: "Strategy"});
        vm.label({account: address(allocator), newLabel: "Allocator"});
        vm.label({account: address(accountant), newLabel: "Accountant"});
        vm.label({account: address(rewardToken), newLabel: "Reward Token"});
        vm.label({account: address(protocolController), newLabel: "Protocol Controller"});
    }

    function _afterSetup() internal virtual {
        /// 1. Set strategy in protocol controller.
        protocolController.setStrategy(protocolId, strategy);
        protocolController.setAllocator(protocolId, address(allocator));

        /// 2. Set factory as registrar.
        protocolController.setRegistrar(address(factory), true);

        /// 3. Enable modules in the gateway Safe.
        _enableModule(address(factory));
        _enableModule(address(strategy));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      GATEWAY UTILITIES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enables a module in the gateway Safe.
    /// @param moduleAddress The module to enable.
    function _enableModule(address moduleAddress) internal {
        /// Build signatures
        bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

        // Execute transaction
        SafeLibrary.simpleExec({
            _safe: payable(gateway),
            _target: address(gateway),
            _data: abi.encodeWithSelector(IModuleManager.enableModule.selector, moduleAddress),
            _signatures: signatures
        });
    }

    /// @notice Disables a module in the gateway Safe.
    /// @param moduleAddress The module to disable.
    function _disableModule(address moduleAddress) internal {
        /// Build signatures
        bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

        // Execute transaction
        SafeLibrary.simpleExec({
            _safe: payable(gateway),
            _target: address(gateway),
            _data: abi.encodeWithSelector(IModuleManager.disableModule.selector, moduleAddress),
            _signatures: signatures
        });
    }

    /// @notice Utility function to ensure a fuzzed address has not been previously labeled
    function _assumeUnlabeledAddress(address fuzzedAddress) internal view {
        vm.assume(bytes10(bytes(vm.getLabel(fuzzedAddress))) == bytes10(bytes("unlabeled:")));
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }
}
