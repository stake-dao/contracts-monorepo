// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";
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

    /// @notice Salt seed for deterministic deployments
    /// @dev Change this to a fixed value for consistent deployments across sessions
    uint256 public constant SEED = 1;

    /// @notice Array of supported chains for deployment
    string[] public deploymentChains = ["mainnet", "arbitrum", "optimism", "base"];

    /// @notice Salt for CREATE3 deployment
    /// @dev Following the pattern: STAKEDAO.STRATEGIES.V1.{contractName}.{seed}
    function getSalt() public pure returns (bytes32) {
        return keccak256(abi.encodePacked("STAKEDAO.STRATEGIES.V1.", type(UniversalBoostRegistry).name, ".", SEED));
    }

    /// @notice Main deployment function that deploys on all specified chains
    function run() public {
        console.log("Starting UniversalBoostRegistry deployment on multiple chains...");
        console.log("Using CREATE3 Factory:", CREATE3_FACTORY);
        console.log("Using Salt:", vm.toString(getSalt()));

        bytes memory creationCode = type(UniversalBoostRegistry).creationCode;
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);

        for (uint256 i = 0; i < deploymentChains.length; i++) {
            _deploy(deploymentChains[i], creationCode, deployerPrivateKey);
        }
    }

    /// @notice Deploy the contract on a specific chain
    /// @param chainName The name of the chain to deploy on
    /// @param creationCode The bytecode of the contract to deploy
    /// @param deployerPrivateKey The private key of the deployer
    function _deploy(string memory chainName, bytes memory creationCode, uint256 deployerPrivateKey) internal {
        console.log(string.concat("\nDeploying on ", chainName, "..."));

        vm.createSelectFork(chainName);

        vm.startBroadcast(deployerPrivateKey);
        address deployedAddress = ICreate3Factory(CREATE3_FACTORY).deployCreate3(getSalt(), creationCode);
        vm.stopBroadcast();

        console.log(string.concat("Deployed at: ", vm.toString(deployedAddress)));
    }
}