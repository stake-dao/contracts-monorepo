// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {sdMAVOft} from "src/mav/token/sdMAVOft.sol";

contract SetTrustedRemoteOft is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    sdMAVOft public sdMavOftEth;
    sdMAVOft public sdMavOftBase;
    sdMAVOft public sdMavOftBnb;
    sdMAVOft public sdMavOftZkSync;

    uint8 ethereumChainId = 101;
    uint8 baseChainId = 184;
    uint8 bnbChainId = 102;
    uint8 zkSyncEra = 165;

    function run() public {
        vm.startBroadcast(deployer);
        string memory rpcUrl = vm.envString("FOUNDRY_ETH_RPC_URL");
        bytes32 rpcUrlHash = keccak256(abi.encodePacked((rpcUrl)));
        bytes memory sdMavOftEthBytes = abi.encodePacked(address(sdMavOftEth));
        bytes memory sdMavOftBaseBytes = abi.encodePacked(address(sdMavOftBase));
        bytes memory sdMavOftBnbBytes = abi.encodePacked(address(sdMavOftBnb));
        bytes memory sdMavOftZkSyncBytes = abi.encodePacked(address(sdMavOftZkSync));
        if (keccak256(abi.encodePacked(vm.rpcUrl("ethereum"))) == rpcUrlHash) {
            sdMavOftEth.setTrustedRemoteAddress(184, sdMavOftBaseBytes);
            sdMavOftEth.setTrustedRemoteAddress(102, sdMavOftBnbBytes);
            sdMavOftEth.setTrustedRemoteAddress(165, sdMavOftZkSyncBytes);
        }
        if (keccak256(abi.encodePacked(vm.rpcUrl("base"))) == rpcUrlHash) {
            sdMavOftBase.setTrustedRemoteAddress(101, sdMavOftEthBytes);
            sdMavOftBase.setTrustedRemoteAddress(102, sdMavOftBnbBytes);
            sdMavOftBase.setTrustedRemoteAddress(165, sdMavOftZkSyncBytes);
        }
        if (keccak256(abi.encodePacked(vm.rpcUrl("bnb"))) == rpcUrlHash) {
            sdMavOftBnb.setTrustedRemoteAddress(184, sdMavOftBaseBytes);
            sdMavOftBnb.setTrustedRemoteAddress(101, sdMavOftEthBytes);
            sdMavOftBnb.setTrustedRemoteAddress(165, sdMavOftZkSyncBytes);
        }
        if (keccak256(abi.encodePacked(vm.rpcUrl("zkSync"))) == rpcUrlHash) {
            sdMavOftZkSync.setTrustedRemoteAddress(184, sdMavOftBaseBytes);
            sdMavOftZkSync.setTrustedRemoteAddress(102, sdMavOftBnbBytes);
            sdMavOftZkSync.setTrustedRemoteAddress(101, sdMavOftEthBytes);
        }
        vm.stopBroadcast();
    }
}