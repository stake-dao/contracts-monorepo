// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "forge-std/src/Script.sol";

import {Allocator} from "src/Allocator.sol";
import {Safe, SafeLibrary} from "test/utils/SafeLibrary.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {OwnerManager} from "@safe-global/safe-smart-account/contracts/base/OwnerManager.sol";
import {IModuleManager} from "@interfaces/safe/IModuleManager.sol";
import {CommonUniversal} from "address-book/src/CommonUniversal.sol";

import {Accountant} from "src/Accountant.sol";
import {RewardReceiver} from "src/RewardReceiver.sol";
import {RewardVault, IStrategy} from "src/RewardVault.sol";
import {ProtocolController} from "src/ProtocolController.sol";
import {Create3} from "shared/src/create/Create3.sol";

abstract contract BaseDeploy is Script {
    address public admin;
    address public feeReceiver;
    address public deployer;

    bytes4 internal protocolId;
    address public rewardToken;
    IStrategy.HarvestPolicy internal harvestPolicy;

    address public locker;
    Safe public gateway;

    Allocator public allocator;
    Accountant public accountant;
    ProtocolController public protocolController;

    address public strategy;

    address public factory;
    RewardVault public rewardVaultImplementation;
    RewardReceiver public rewardReceiverImplementation;

    address public sidecarFactory;
    address public sidecarImplementation;

    address[] public owners;

    /// @notice Base salt prefix for all CREATE3 deployments
    string internal constant BASE_SALT = "STAKEDAO.STRATEGIES";

    modifier doSetup(
        string memory _chain,
        address _rewardToken,
        address _locker,
        bytes4 _protocolId,
        IStrategy.HarvestPolicy _harvestPolicy
    ) {
        vm.createSelectFork(_chain);
        vm.startBroadcast(admin);
        _beforeSetup(_rewardToken, _locker, _protocolId, _harvestPolicy);
        _;
        _afterSetup();
        vm.stopBroadcast();
    }

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
        protocolController = ProtocolController(
            _deployWithCreate3(
                type(ProtocolController).name,
                abi.encodePacked(type(ProtocolController).creationCode, abi.encode(admin))
            )
        );

        /// 2. Set fee receiver.
        protocolController.setFeeReceiver(protocolId, feeReceiver);

        /// 3. Deploy Accountant.
        accountant = Accountant(
            _deployWithCreate3(
                type(Accountant).name,
                abi.encodePacked(
                    type(Accountant).creationCode,
                    abi.encode(admin, address(protocolController), address(rewardToken), protocolId)
                )
            )
        );

        /// 4. Deploy Reward Vault Implementation.
        rewardVaultImplementation = RewardVault(
            _deployWithCreate3(
                type(RewardVault).name,
                abi.encodePacked(
                    type(RewardVault).creationCode,
                    abi.encode(protocolId, address(protocolController), address(accountant), harvestPolicy)
                )
            )
        );

        /// 5. Deploy Reward Receiver Implementation.
        rewardReceiverImplementation = RewardReceiver(
            _deployWithCreate3(type(RewardReceiver).name, abi.encodePacked(type(RewardReceiver).creationCode))
        );

        owners = new address[](1);
        owners[0] = admin;

        /// 6. Deploy Gateway.
        gateway = _deployGateway();

        /// 7. Setup contracts in protocol controller.
        protocolController.setAccountant(protocolId, address(accountant));

        /// 8. Deploy Allocator.
        allocator = Allocator(
            _deployWithCreate3(
                type(Allocator).name,
                abi.encodePacked(type(Allocator).creationCode, abi.encode(locker, address(gateway)))
            )
        );
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

        /// 4. If sidecar factory is set, enable it.
        if (sidecarFactory != address(0)) {
            /// Allow sidecar factory to be used as a registrar.
            protocolController.setRegistrar(address(sidecarFactory), true);

            /// Enable sidecar factory.
            _enableModule(address(sidecarFactory));
        }

        /// 5. Transfer ownership of all contracts to GATEWAY and GATEWAY to GOVERNANCE.
        /// 5.a Transfer Accountant to GATEWAY.
        accountant.transferOwnership(address(gateway));

        /// 5.b Transfer Protocol Controller to GATEWAY.
        protocolController.transferOwnership(address(gateway));

        /// Build signatures
        bytes memory signatures = abi.encodePacked(uint256(uint160(admin)), uint8(0), uint256(1));

        SafeLibrary.simpleExec({
            _safe: payable(gateway),
            _target: address(accountant),
            _data: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            _signatures: signatures
        });

        SafeLibrary.simpleExec({
            _safe: payable(gateway),
            _target: address(protocolController),
            _data: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
            _signatures: signatures
        });

        /// If not mainnet, transfer ownership of the factory to GOVERNANCE.
        if (block.chainid != 1) {
            /// Transfer ownership of the factory to GATEWAY.
            Ownable2Step(factory).transferOwnership(address(gateway));

            /// Accept ownership of the factory.
            SafeLibrary.simpleExec({
                _safe: payable(gateway),
                _target: address(factory),
                _data: abi.encodeWithSelector(Ownable2Step.acceptOwnership.selector),
                _signatures: signatures
            });
        }

        /// Transfer ownership of all the contracts to GOVERNANCE.
        SafeLibrary.simpleExec({
            _safe: payable(gateway),
            _target: address(gateway),
            _data: abi.encodeWithSelector(OwnerManager.swapOwner.selector, address(1), admin, CommonUniversal.GOVERNANCE),
            _signatures: signatures
        });
    }

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

    function _deployGateway() internal virtual returns (Safe) {
        return SafeLibrary.deploySafe({_owners: owners, _threshold: 1, _saltNonce: uint256(uint32(protocolId))});
    }

    /// @notice Generates a deterministic salt for CREATE3 deployments
    /// @param contractType The type of contract being deployed (e.g., "STRATEGY", "CONTROLLER")
    /// @return The generated salt
    function _getSalt(string memory contractType) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(BASE_SALT, ".", protocolId, ".", contractType, ".V1"));
    }

    /// @notice Deploy a contract using CREATE3 for deterministic cross-chain addresses
    /// @param contractType The type of contract being deployed (e.g., "STRATEGY", "FACTORY", "SIDECAR")
    /// @param bytecode The creation bytecode including constructor arguments
    /// @return deployed The deployed contract address
    function _deployWithCreate3(string memory contractType, bytes memory bytecode)
        internal
        returns (address deployed)
    {
        bytes32 salt = _getSalt(contractType);
        deployed = Create3.deployCreate3(salt, bytecode);
    }

    /// @notice Computes the address where a contract will be deployed with CREATE3
    /// @param contractType The type of contract
    /// @return The computed address
    function computeCreate3Address(string memory contractType) public view returns (address) {
        bytes32 salt = _getSalt(contractType);
        return Create3.computeCreate3Address(salt);
    }
}
