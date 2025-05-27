// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {YieldnestOFTAdapter} from "src/integrations/yieldnest/YieldnestOFTAdapter.sol";
import {YieldnestOFT} from "src/integrations/yieldnest/YieldnestOFT.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";
import {LayerZeroEID} from "src/libraries/LayerZeroEID.sol";

/// @notice Script to deploy and configure the Yieldnest omnichain protocol using LayerZero V2.
/// @dev This script deploys the YieldnestOFT (BSC) and YieldnestOFTAdapter (Mainnet) contracts, sets up LayerZero trusted peers,
///      and transfers ownership to the DAO governance address.
///
///      Deployment Flow:
///      1. Precompute the address of the YieldnestOFTAdapter contract on mainnet (source chain).
///      2. Deploy the YieldnestOFT contract on BSC (destination chain) and set the mainnet adapter as its trusted peer.
///      3. Transfer ownership of the YieldnestOFT contract to the DAO governance address.
///      4. Deploy the YieldnestOFTAdapter contract on mainnet and set the BSC OFT as its trusted peer.
///      5. Transfer ownership of the YieldnestOFTAdapter contract to the DAO governance address.
///
///      LayerZero Configuration:
///      - The setPeer function establishes the trusted relationship between the OFT and OFTAdapter contracts across chains.
///      - The LayerZeroEID library provides the correct endpoint IDs (eids) for mainnet and BSC.
///
///      Environment Variables:
///      - ASDYND: Address of the asdYND ERC20 token on mainnet.
///      - SOURCE_RPC: (Optional) RPC URL for mainnet. Defaults to the standard mainnet RPC.
///      - DESTINATION_RPC: (Optional) RPC URL for BSC. Defaults to the standard BSC RPC.
///
///      For more information on LayerZero and omnichain deployment, see:
///      https://docs.layerzero.network/v2/developers/evm/oft/quickstart
contract DeployYieldnestOFTProtocolScript is Script {
    /// @return yieldnestOFTAdapter The deployed YieldnestOFTAdapter contract on the source chain (mainnet).
    /// @return yieldnestOFT The deployed YieldnestOFT contract on the destination chain (bsc).
    function run() external returns (YieldnestOFTAdapter yieldnestOFTAdapter, YieldnestOFT yieldnestOFT) {
        // @dev: Mandatory env variable that specify the address of the protocol controller
        address token = vm.envAddress("ASDYND");

        // @dev: Optional env variable that lets the developers override the RPC url of both chains
        //       This is useful for local development.
        string memory sourceRPC = vm.envOr("SOURCE_RPC", vm.rpcUrl("mainnet"));
        string memory destinationRPC = vm.envOr("DESTINATION_RPC", vm.rpcUrl("bnb"));

        //////////////////////////////////////////////////////
        // --- SOURCE CHAIN (MAINNET)
        //////////////////////////////////////////////////////

        // 1. Compute the address the `YieldnestOFTAdapter` contract will be deployed at on the source chain
        vm.createSelectFork(sourceRPC);
        address deployer = msg.sender;
        uint256 deployerNonce = vm.getNonce(deployer);
        address yieldnestOFTAdapterAddress = vm.computeCreateAddress(deployer, deployerNonce);

        //////////////////////////////////////////////////////
        // --- DESTINATION CHAIN (BSC)
        //////////////////////////////////////////////////////

        vm.createSelectFork(destinationRPC);
        vm.startBroadcast();

        // 2. Deploy the `YieldnestOFT` contract on the destination chain and set the governance address as the first delegate
        yieldnestOFT = new YieldnestOFT(DAO.GOVERNANCE);

        // 3. Set the `YieldnestOFTAdapter` contract that will be deployed on the source chain as the first authorized peer
        //    The address of the contract must be encoded in bytes32 following the documentation
        yieldnestOFT.setPeer(LayerZeroEID.MAINNET_EID, bytes32(bytes20(address(yieldnestOFTAdapterAddress))));

        // 4. Transfer the ownership of the `YieldnestOFT` contract to the DAO governance address
        yieldnestOFT.transferOwnership(DAO.GOVERNANCE);
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        // --- SOURCE CHAIN (MAINNET)
        //////////////////////////////////////////////////////

        vm.createSelectFork(sourceRPC);
        vm.startBroadcast();

        // 5. Deploy the `YieldnestOFTAdapter` contract on the source chain and set the governance address as the first delegate
        yieldnestOFTAdapter = new YieldnestOFTAdapter(token, DAO.GOVERNANCE);

        // 6. Assert that the `YieldnestOFTAdapter` contract has been deployed at the expected address or revert
        require(
            address(yieldnestOFTAdapter) == yieldnestOFTAdapterAddress,
            "Issue with the address precomputation of the YieldnestOFTAdapter contract. Abort."
        );

        // 7. Set the `YieldnestOFT` contract that has been deployed on the destination chain as the first authorized peer
        //    The address of the contract must be encoded in bytes32 following the documentation
        yieldnestOFTAdapter.setPeer(LayerZeroEID.BSC_EID, bytes32(bytes20(address(yieldnestOFT))));

        // 8. Transfer the ownership of the `YieldnestOFTAdapter` contract to the DAO governance address
        yieldnestOFTAdapter.transferOwnership(DAO.GOVERNANCE);

        vm.stopBroadcast();
    }
}
