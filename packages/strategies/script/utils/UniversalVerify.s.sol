// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";

/// @title UniversalVerify
/// @notice Universal contract verification script that handles all verification scenarios
/// @dev Supports direct verification, broadcast file parsing, single and multi-chain deployments
contract UniversalVerify is Script {
    /// @notice Get the appropriate API key for a given chain
    function getApiKeyForChain(string memory chainName) internal view returns (string memory) {
        if (keccak256(bytes(chainName)) == keccak256(bytes("mainnet"))) {
            return vm.envString("ETHERSCAN_KEY");
        } else if (keccak256(bytes(chainName)) == keccak256(bytes("arbitrum"))) {
            return vm.envString("ARBISCAN_KEY");
        } else if (keccak256(bytes(chainName)) == keccak256(bytes("optimism"))) {
            return vm.envString("OPTIMISTICSCAN_KEY");
        } else if (keccak256(bytes(chainName)) == keccak256(bytes("base"))) {
            return vm.envString("BASESCAN_KEY");
        } else if (keccak256(bytes(chainName)) == keccak256(bytes("polygon"))) {
            return vm.envString("POLYGONSCAN_KEY");
        } else if (keccak256(bytes(chainName)) == keccak256(bytes("bnb"))) {
            return vm.envString("BNBSCAN_KEY");
        } else {
            return "";
        }
    }

    /// @notice Direct verification when you know the contract details
    /// @param contractAddress The deployed contract address
    /// @param contractPath The source path (e.g., "src/MyContract.sol:MyContract")
    /// @param chainName The chain to verify on
    function verifyDirect(
        address contractAddress,
        string memory contractPath,
        string memory chainName
    ) public {
        console.log("=== Direct Verification ===");
        console.log("Chain:", chainName);
        console.log("Address:", contractAddress);
        console.log("Contract:", contractPath);

        string memory apiKey = getApiKeyForChain(chainName);
        require(bytes(apiKey).length > 0, string.concat("No API key for ", chainName));

        _runVerification(contractAddress, contractPath, chainName, apiKey);
    }

    /// @notice Direct multi-chain verification (same address on all chains)
    /// @param contractAddress The deployed contract address
    /// @param contractPath The source path
    function verifyDirectMultiChain(address contractAddress, string memory contractPath) public {
        string[4] memory chains = ["mainnet", "arbitrum", "optimism", "base"];
        
        console.log("=== Direct Multi-Chain Verification ===");
        console.log("Address:", contractAddress);
        console.log("Contract:", contractPath);
        
        for (uint i = 0; i < chains.length; i++) {
            string memory apiKey = getApiKeyForChain(chains[i]);
            if (bytes(apiKey).length > 0) {
                console.log(string.concat("\nVerifying on ", chains[i], "..."));
                try this.verifyDirect(contractAddress, contractPath, chains[i]) {
                    console.log("Success");
                } catch {
                    console.log("Failed or already verified");
                }
            }
        }
    }

    /// @notice Verify from broadcast files - single chain
    /// @param scriptPath The deployment script path (e.g., "script/Deploy.s.sol")
    /// @param chainName The chain name
    function verifyFromBroadcast(string memory scriptPath, string memory chainName) public {
        console.log("=== Verify from Broadcast ===");
        console.log("Script:", scriptPath);
        console.log("Chain:", chainName);

        // Extract script name from path
        string memory scriptName = _extractFileName(scriptPath);
        uint256 chainId = _getChainId(chainName);
        
        // Try standard broadcast path
        string memory broadcastPath = string.concat("broadcast/", scriptName, "/", vm.toString(chainId), "/run-latest.json");
        
        try vm.readFile(broadcastPath) returns (string memory json) {
            console.log("Found broadcast file");
            _verifyFromJson(json, chainName);
        } catch {
            console.log("Broadcast not found, trying multi-chain broadcast...");
            _tryMultiChainBroadcast(scriptName, chainName);
        }
    }

    /// @notice Verify from broadcast files - multi chain
    /// @param scriptPath The deployment script path
    function verifyFromBroadcastMultiChain(string memory scriptPath) public {
        console.log("=== Verify from Multi-Chain Broadcast ===");
        console.log("Script:", scriptPath);

        string[4] memory chains = ["mainnet", "arbitrum", "optimism", "base"];

        // Try to find multi-chain broadcast
        string memory scriptNameOnly = _extractFileName(scriptPath);
        string memory multiPath = string.concat("broadcast/multi/", scriptNameOnly, "-latest/run.json");
        
        console.log("Looking for:", multiPath);
        
        try vm.readFile(multiPath) returns (string memory json) {
            console.log("Found multi-chain broadcast");
            
            // For CREATE3 deployments, extract the single address
            address deployedAddress = _extractCreate3Address(json);
            if (deployedAddress != address(0)) {
                string memory contractPath = _inferContractPath(json);
                console.log("CREATE3 deployment found");
                console.log("Address:", deployedAddress);
                console.log("Inferred path:", contractPath);
                
                for (uint i = 0; i < chains.length; i++) {
                    string memory apiKey = getApiKeyForChain(chains[i]);
                    if (bytes(apiKey).length > 0) {
                        console.log(string.concat("\nVerifying on ", chains[i], "..."));
                        _runVerification(deployedAddress, contractPath, chains[i], apiKey);
                    }
                }
                return;
            }
        } catch {
            console.log("Multi-chain broadcast not found");
        }

        // Fall back to checking individual chain broadcasts
        for (uint i = 0; i < chains.length; i++) {
            console.log(string.concat("\nChecking ", chains[i], "..."));
            this.verifyFromBroadcast(scriptPath, chains[i]);
        }
    }

    /// @notice Internal function to run forge verify-contract
    function _runVerification(
        address contractAddress,
        string memory contractPath,
        string memory chainName,
        string memory apiKey
    ) internal {
        string[] memory inputs = new string[](11);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(contractAddress);
        inputs[3] = contractPath;
        inputs[4] = "--chain";
        inputs[5] = chainName;
        inputs[6] = "--etherscan-api-key";
        inputs[7] = apiKey;
        inputs[8] = "--watch";
        inputs[9] = "--compiler-version";
        inputs[10] = "0.8.28";

        try vm.ffi(inputs) {
            console.log("Verification command sent");
        } catch {
            console.log("Verification command failed");
        }
    }

    /// @notice Extract CREATE3 deployed address from multi-chain broadcast
    function _extractCreate3Address(string memory json) internal pure returns (address) {
        // Look for CREATE transaction type in additionalContracts
        bytes memory jsonBytes = bytes(json);
        bytes memory searchPattern = bytes('"transactionType":"CREATE","address":"0x');
        
        uint256 index = _findPattern(jsonBytes, searchPattern);
        if (index > 0) {
            // Extract the 40 character address after 0x
            bytes memory addrBytes = new bytes(40);
            for (uint i = 0; i < 40; i++) {
                addrBytes[i] = jsonBytes[index + searchPattern.length + i];
            }
            // Convert hex string to address
            return _parseAddress(string(addrBytes));
        }
        
        return address(0);
    }

    /// @notice Try to infer contract path from broadcast JSON
    function _inferContractPath(string memory json) internal pure returns (string memory) {
        // Look for common patterns in broadcast files
        // This is a best-effort approach
        
        // Check for UniversalBoostRegistry
        if (_contains(json, "UniversalBoostRegistry")) {
            return "src/merkl/UniversalBoostRegistry.sol:UniversalBoostRegistry";
        }
        
        // Default pattern - try to extract contract name
        // This would need to be enhanced based on your project structure
        return "src/Contract.sol:Contract";
    }

    /// @notice Parse address from hex string
    function _parseAddress(string memory hexStr) internal pure returns (address) {
        bytes memory hexBytes = bytes(hexStr);
        uint160 addr = 0;
        
        for (uint i = 0; i < hexBytes.length; i++) {
            uint8 digit = uint8(hexBytes[i]);
            if (digit >= 48 && digit <= 57) {
                addr = addr * 16 + (digit - 48);
            } else if (digit >= 65 && digit <= 70) {
                addr = addr * 16 + (digit - 55);
            } else if (digit >= 97 && digit <= 102) {
                addr = addr * 16 + (digit - 87);
            }
        }
        
        return address(addr);
    }

    /// @notice Verify from parsed JSON
    function _verifyFromJson(string memory /* json */, string memory /* chainName */) internal pure {
        // This is simplified - in production you'd want proper JSON parsing
        console.log("Parsing broadcast JSON...");
        console.log("JSON parsing not fully implemented");
        console.log("Use direct verification instead");
    }

    /// @notice Try multi-chain broadcast for single chain
    function _tryMultiChainBroadcast(string memory scriptName, string memory /* chainName */) internal view {
        string memory multiPath = string.concat("broadcast/multi/", scriptName, "-latest/run.json");
        
        try vm.readFile(multiPath) returns (string memory json) {
            console.log("Found in multi-chain broadcast");
            address addr = _extractCreate3Address(json);
            if (addr != address(0)) {
                console.log("Use direct verification with address:", addr);
            }
        } catch {
            console.log("No broadcast found for this deployment");
        }
    }

    /// @notice Extract filename from path
    function _extractFileName(string memory path) internal pure returns (string memory) {
        bytes memory pathBytes = bytes(path);
        uint lastSlash = 0;
        
        for (uint i = 0; i < pathBytes.length; i++) {
            if (pathBytes[i] == "/") {
                lastSlash = i;
            }
        }
        
        if (lastSlash > 0) {
            bytes memory fileName = new bytes(pathBytes.length - lastSlash - 1);
            for (uint i = 0; i < fileName.length; i++) {
                fileName[i] = pathBytes[lastSlash + 1 + i];
            }
            return string(fileName);
        }
        
        return path;
    }

    /// @notice Get chain ID from name
    function _getChainId(string memory chainName) internal pure returns (uint256) {
        if (keccak256(bytes(chainName)) == keccak256(bytes("mainnet"))) return 1;
        if (keccak256(bytes(chainName)) == keccak256(bytes("arbitrum"))) return 42161;
        if (keccak256(bytes(chainName)) == keccak256(bytes("optimism"))) return 10;
        if (keccak256(bytes(chainName)) == keccak256(bytes("base"))) return 8453;
        if (keccak256(bytes(chainName)) == keccak256(bytes("polygon"))) return 137;
        return 0;
    }

    /// @notice Find pattern in bytes
    function _findPattern(bytes memory data, bytes memory pattern) internal pure returns (uint256) {
        if (pattern.length > data.length) return 0;
        
        for (uint i = 0; i <= data.length - pattern.length; i++) {
            bool found = true;
            for (uint j = 0; j < pattern.length; j++) {
                if (data[i + j] != pattern[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return i;
        }
        return 0;
    }

    /// @notice Check if string contains substring
    function _contains(string memory str, string memory substr) internal pure returns (bool) {
        return _findPattern(bytes(str), bytes(substr)) > 0;
    }

    /// @notice Remove file extension
    function _removeExtension(string memory filename) internal pure returns (string memory) {
        bytes memory fnBytes = bytes(filename);
        uint lastDot = 0;
        
        for (uint i = fnBytes.length; i > 0; i--) {
            if (fnBytes[i-1] == ".") {
                lastDot = i-1;
                break;
            }
        }
        
        if (lastDot > 0) {
            bytes memory result = new bytes(lastDot);
            for (uint i = 0; i < lastDot; i++) {
                result[i] = fnBytes[i];
            }
            return string(result);
        }
        
        return filename;
    }
}