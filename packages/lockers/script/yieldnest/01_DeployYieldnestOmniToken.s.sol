// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {YieldnestOFTAdapter} from "src/integrations/yieldnest/YieldnestOFTAdapter.sol";
import {YieldnestOFT} from "src/integrations/yieldnest/YieldnestOFT.sol";
import {DAO} from "@address-book/src/DaoEthereum.sol";
import {LayerZeroEID} from "src/libraries/LayerZeroEID.sol";
import {Create3} from "shared/src/create/Create3.sol";
import {YieldnestAutocompoundedVault} from "src/integrations/yieldnest/YieldnestAutocompoundedVault.sol";

/**
 * @title DeployYieldnestOmniTokenScript
 * @notice Unified deployment script for the Yieldnest omnichain protocol (asdYND token and OFT contracts) using LayerZero V2.
 * @dev This script deploys the YieldnestAutocompoundedVault (asdYND) and the omnichain OFT contracts (YieldnestOFT, YieldnestOFTAdapter),
 *      configures LayerZero trusted peers, and transfers ownership to the DAO governance address. Additional safeguards ensure
 *      correct address precomputation and cross-chain configuration.
 *
 *      Deployment Flow:
 *      1. Precompute the address of the YieldnestOFTAdapter contract on mainnet (source chain).
 *      2. Deploy the YieldnestAutocompoundedVault (asdYND) on the source chain (mainnet).
 *      3. Deploy the YieldnestOFT contract on the destination chain (bsc) using CREATE3 with the same salt than the vault.
 *      4. Deploy the YieldnestOFTAdapter contract on the source chain (mainnet) and set the governance address as the first delegate.
 *      5. Set up LayerZero trusted peers between the OFT and OFTAdapter contracts across chains.
 *      6. Transfer ownership of both contracts to the DAO governance address.
 *
 *      LayerZero Configuration:
 *      - The setPeer function establishes the trusted relationship between the OFT and OFTAdapter contracts across chains.
 *      - The LayerZeroEID library provides the correct endpoint IDs (eids) for mainnet and BSC.
 *
 *      Environment Variables:
 *      - ASDYND: Address of the asdYND ERC20 token on mainnet.
 *      - SOURCE_RPC: (Optional) RPC URL for mainnet. Defaults to the standard mainnet RPC.
 *      - DESTINATION_RPC: (Optional) RPC URL for BSC. Defaults to the standard BSC RPC.
 *      - SALT: (Optional) Salt label for deterministic deployment. Defaults to "STAKEDAO.OMNIVAULT.YIELDNEST.V1".
 *
 *      For more information on LayerZero and omnichain deployment, see:
 *      https://docs.layerzero.network/v2/developers/evm/oft/quickstart
 */
contract DeployYieldnestOmniTokenScript is Script {
    function addressToBytes32LeftPadded(address _address) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_address)));
    }

    /// @return yieldnestVault The deployed YieldnestAutocompoundedVault contract on the source chain (mainnet).
    /// @return yieldnestOFTAdapter The deployed YieldnestOFTAdapter contract on the source chain (mainnet).
    /// @return yieldnestOFT The deployed YieldnestOFT contract on the destination chain (bsc).
    function run()
        external
        returns (
            YieldnestAutocompoundedVault yieldnestVault,
            YieldnestOFTAdapter yieldnestOFTAdapter,
            YieldnestOFT yieldnestOFT
        )
    {
        // @dev: Optional env variable that lets the developers override the RPC url of both chains and the salt seed.
        //       This is useful for local development.
        string memory sourceRPC = vm.envOr("SOURCE_RPC", vm.rpcUrl("mainnet"));
        string memory destinationRPC = vm.envOr("DESTINATION_RPC", vm.rpcUrl("bnb"));
        string memory saltLabel = vm.envOr("SALT", string(abi.encodePacked("STAKEDAO.OMNIVAULT.YIELDNEST.V1")));

        // Create both fork that will be used for the deployment
        uint256 sourceForkId = vm.createFork(sourceRPC);
        uint256 destinationForkId = vm.createFork(destinationRPC);

        // Compute the salt that will be used to deploy the asdYND token on the source chain (mainnet) and the
        // OFT contract on the destination chain (bsc)
        bytes32 salt = keccak256(abi.encodePacked(saltLabel));

        //////////////////////////////////////////////////////
        // --- SOURCE CHAIN (MAINNET)
        //////////////////////////////////////////////////////
        vm.selectFork(sourceForkId);
        vm.startBroadcast();

        // Deploy the YieldnestAutocompoundedVault contract
        yieldnestVault = YieldnestAutocompoundedVault(
            Create3.deployCreate3(
                salt, abi.encodePacked(type(YieldnestAutocompoundedVault).creationCode, abi.encode(DAO.GOVERNANCE))
            )
        );

        // Compute the final address of the `YieldnestOFTAdapter` contract that will be deployed at on the source chain
        address deployer = msg.sender;
        uint256 deployerNonce = vm.getNonce(deployer);
        address yieldnestOFTAdapterAddress = vm.computeCreateAddress(deployer, deployerNonce);

        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        // --- DESTINATION CHAIN (BSC)
        //////////////////////////////////////////////////////

        vm.selectFork(destinationForkId);
        vm.startBroadcast();

        // Deploy the `YieldnestOFT` contract on the destination chain, set the governance address as the first delegate and
        //    the caller as the temporary owner of the contract
        yieldnestOFT = YieldnestOFT(
            Create3.deployCreate3(
                salt, abi.encodePacked(type(YieldnestOFT).creationCode, abi.encode(DAO.GOVERNANCE, msg.sender))
            )
        );

        require(address(yieldnestVault) == address(yieldnestOFT), "Issue with the CREATE3 deployments. Abort.");

        // Set the `YieldnestOFTAdapter` contract that will be deployed on the source chain as the first authorized peer
        //    The address of the contract must be encoded in bytes32 following the documentation
        yieldnestOFT.setPeer(LayerZeroEID.MAINNET_EID, addressToBytes32LeftPadded(address(yieldnestOFTAdapterAddress)));

        // Transfer the ownership of the `YieldnestOFT` contract to the DAO governance address
        yieldnestOFT.transferOwnership(DAO.GOVERNANCE);
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        // --- SOURCE CHAIN (MAINNET)
        //////////////////////////////////////////////////////

        vm.selectFork(sourceForkId);
        vm.startBroadcast();

        // Deploy the `YieldnestOFTAdapter` contract on the source chain and set the governance address as the first delegate
        yieldnestOFTAdapter = new YieldnestOFTAdapter(address(yieldnestVault), DAO.GOVERNANCE, msg.sender);

        // Assert that the `YieldnestOFTAdapter` contract has been deployed at the expected address or revert
        require(
            address(yieldnestOFTAdapter) == yieldnestOFTAdapterAddress,
            "Issue with the address precomputation of the YieldnestOFTAdapter contract. Abort."
        );

        // Set the `YieldnestOFT` contract that has been deployed on the destination chain as the first authorized peer
        // The address of the contract must be encoded in bytes32 following the documentation
        yieldnestOFTAdapter.setPeer(LayerZeroEID.BSC_EID, addressToBytes32LeftPadded(address(yieldnestOFT)));

        // Transfer the ownership of the `YieldnestOFTAdapter` contract to the DAO governance address
        yieldnestOFTAdapter.transferOwnership(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
