// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {sdMAVOft} from "src/mav/token/sdMAVOft.sol";

contract DeploySdMAVOft is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public lzEndpointEth = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
    address public lzEndpointBase = 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;
    address public lzEndpointBnb = 0x3c2269811836af69497E5F486A85D7316753cf62;
    address public lzEndpointZkSyncEra = 0x9b896c0e23220469C7AE69cb4BbAE391eAa4C8da;
    
    sdMAVOft sdMav;
    function run() public {
        vm.startBroadcast(deployer);
        string memory rpcUrl = vm.envString("FOUNDRY_ETH_RPC_URL");
        emit log_string(rpcUrl);
        emit log_string(vm.rpcUrl("zkSync"));
        string memory tokenName = "Stake DAO MAV";
        string memory tokenSymbol = "sdMAV";
        bytes32 rpcUrlHash = keccak256(abi.encodePacked((rpcUrl)));
        if (keccak256(abi.encodePacked(vm.rpcUrl("ethereum"))) == rpcUrlHash) {
            sdMav = new sdMAVOft(tokenName, tokenSymbol, lzEndpointEth);
        }
        if (keccak256(abi.encodePacked(vm.rpcUrl("base"))) == rpcUrlHash) {
            sdMav = new sdMAVOft(tokenName, tokenSymbol, lzEndpointBase);
        }
        if (keccak256(abi.encodePacked(vm.rpcUrl("bnb"))) == rpcUrlHash) {
            sdMav = new sdMAVOft(tokenName, tokenSymbol, lzEndpointBnb);
        }
        if (keccak256(abi.encodePacked(vm.rpcUrl("zkSync"))) == rpcUrlHash) {
            sdMav = new sdMAVOft(tokenName, tokenSymbol, lzEndpointZkSyncEra);
        } 
        vm.stopBroadcast();
    }
}