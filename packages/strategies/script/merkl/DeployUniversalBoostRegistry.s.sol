// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";
import {DAO} from "address-book/src/DAOBase.sol";
import {CommonUniversal} from "address-book/src/CommonUniversal.sol";
import {UniversalBoostRegistry} from "src/merkl/UniversalBoostRegistry.sol";

interface ICreate3Factory {
    function deployCreate3(bytes32 salt, bytes memory creationCode) external returns (address deployed);
}

/// @title DeployUniversalBoostRegistry
/// @notice Deployment script for UniversalBoostRegistry contract using CREATE3 for deterministic addresses
/// @dev This script deploys the UniversalBoostRegistry on multiple chains using CREATE3 to ensure
///      the same contract address across all supported networks.
contract DeployUniversalBoostRegistry is Script {
    /// @notice CREATE3 factory address from the address book
    address public constant CREATE3_FACTORY = CommonUniversal.CREATE3_FACTORY;

    /// @notice Array of supported chains for deployment
    string[] public deploymentChains = ["mainnet", "arbitrum", "optimism", "base", "bnb"];

    /// @notice Salt for CREATE3 deployment
    /// @dev Following the pattern: STAKEDAO.STRATEGIES.V1.{contractName}.{seed}
    function getSalt() public returns (bytes32) {
        return keccak256(
            abi.encodePacked("STAKEDAO.STRATEGIES.V1.", type(UniversalBoostRegistry).name, ".", vm.randomUint())
        );
    }

    /// @notice Main deployment function that deploys on all specified chains
    function run() public {
        console.log("Starting UniversalBoostRegistry deployment on multiple chains...");
        console.log("Using CREATE3 Factory:", CREATE3_FACTORY);

        bytes32 salt = getSalt();
        console.log("Using Salt:", vm.toString(salt));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        bytes memory creationCode = type(UniversalBoostRegistry).creationCode;
        bytes memory constructorArgs = abi.encode(DAO.GOVERNANCE);
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        console.log("Deployer address:", deployer);

        for (uint256 i = 0; i < deploymentChains.length; i++) {
            _deploy(deploymentChains[i], salt, creationCodeWithArgs, deployerPrivateKey);
        }
    }

    /// @notice Deploy the contract on a specific chain
    /// @param chainName The name of the chain to deploy on
    /// @param salt The salt for the deployment
    /// @param creationCodeWithArgs The bytecode of the contract to deploy with constructor arguments
    /// @param deployerPrivateKey The private key of the deployer
    function _deploy(
        string memory chainName,
        bytes32 salt,
        bytes memory creationCodeWithArgs,
        uint256 deployerPrivateKey
    ) internal {
        console.log(string.concat("\nDeploying on ", chainName, "..."));

        vm.createSelectFork(chainName);

        vm.startBroadcast(deployerPrivateKey);
        address deployedAddress = ICreate3Factory(CREATE3_FACTORY).deployCreate3(salt, creationCodeWithArgs);
        vm.stopBroadcast();

        console.log(string.concat("Deployed at: ", vm.toString(deployedAddress)));
    }
}
