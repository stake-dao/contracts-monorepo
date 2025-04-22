// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {Enum} from "@safe/contracts/common/Enum.sol";
import "forge-std/src/Script.sol";
import {Accountant} from "src/Accountant.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {RewardVault, IStrategy} from "src/RewardVault.sol";
import {Safe, SafeLibrary} from "test/utils/SafeLibrary.sol";

abstract contract Base is Script {
    address public deployer;

    address public locker;
    Safe public gateway;

    Accountant public accountant;
    ProtocolController public protocolController;

    RewardVault public rewardVault;
    RewardVault public rewardVaultImplementation;

    RewardReceiver public rewardReceiver;
    RewardReceiver public rewardReceiverImplementation;

    address public strategy;

    function _run(address _deployer, address _rewardToken, address _locker, bytes4 _protocolId, bool _harvested)
        internal
    {
        locker = _locker;
        deployer = _deployer;

        /// 1. Deploy Protocol Controller.
        protocolController = new ProtocolController();

        /// 2. Deploy Accountant.
        accountant = new Accountant({
            _owner: deployer,
            _registry: address(protocolController),
            _rewardToken: address(_rewardToken),
            _protocolId: _protocolId
        });

        /// 3. Deploy Reward Vault Implementation.
        rewardVaultImplementation = new RewardVault({
            protocolId: _protocolId,
            protocolController: address(protocolController),
            accountant: address(accountant),
            policy: _harvested ? IStrategy.HarvestPolicy.HARVEST : IStrategy.HarvestPolicy.CHECKPOINT
        });

        /// 4. Deploy Reward Receiver Implementation.
        rewardReceiverImplementation = new RewardReceiver();

        address[] memory owners = new address[](1);
        owners[0] = deployer;

        /// Generate a salt for the Safe.
        uint256 _saltNonce = _computeSalt({protocolId: _protocolId, version: 1, label: type(Safe).name});

        /// 5. Deploy Gateway.
        /// @dev Before continuing, we need to put this Safe as the owner of the LOCKER.
        gateway = SafeLibrary.deploySafe({_owners: owners, _threshold: 1, _saltNonce: _saltNonce});

        if (address(locker) == address(0)) {
            locker = address(gateway);
        }

        /// 6. Setup contracts in protocol controller.
        protocolController.setFeeReceiver(_protocolId, deployer);

        /// 7. Setup the accountant in the protocol controller.
        protocolController.setAccountant(_protocolId, address(accountant));
    }

    //////////////////////////////////////////////////////
    // --- HELPER FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Enable a module on the gateway
    function _enableModule(address _module) internal {
        bytes memory signatures = abi.encodePacked(uint256(uint160(deployer)), uint8(0), uint256(1));
        gateway.execTransaction(
            address(gateway),
            0,
            abi.encodeWithSelector(IModuleManager.enableModule.selector, _module),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signatures
        );
    }

    function _executeTransaction(address target, bytes memory data) internal returns (bool success) {
        bytes memory signatures = abi.encodePacked(uint256(uint160(deployer)), uint8(0), uint256(1));

        if (locker == address(gateway)) {
            // If locker is the gateway, execute directly on the target
            success = gateway.execTransaction(
                target, 0, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(0), signatures
            );
        } else {
            // Otherwise execute through the locker's execute function
            success = gateway.execTransaction(
                locker,
                0,
                abi.encodeWithSignature("execute(address,uint256,bytes)", target, 0, data),
                Enum.Operation.Call,
                0,
                0,
                0,
                address(0),
                payable(0),
                signatures
            );
        }
    }

    function _computeSalt(bytes4 protocolId, uint16 version, string memory label)
        internal
        view
        returns (uint256 salt)
    {
        salt = uint256(
            keccak256(
                abi.encodePacked(
                    bytes4(protocolId), // 4  bytes
                    uint32(block.chainid), // 4  bytes – makes sidechains and mainnet diverge
                    deployer, // 20 bytes
                    version, // 2  bytes – or uint16/uint32 to taste
                    label // 6+ bytes – arbitrary label so future salts
                )
            )
        );
    }
}
