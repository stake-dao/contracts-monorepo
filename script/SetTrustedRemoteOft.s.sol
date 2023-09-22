// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {sdMAV} from "src/mav/token/sdMAV.sol";

abstract contract SetTrustedRemoteOft is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    // hardcode the addresses before using the scripts 
    sdMAV public sdMavOftEth;
    sdMAV public sdMavOftBase; 
    sdMAV public sdMavOftBnb;
    sdMAV public sdMavOftZkSync;

    uint8 ethereumChainId = 101;
    uint8 baseChainId = 184;
    uint8 bnbChainId = 102;
    uint8 zkSyncEra = 165;

    bytes sdMavOftEthBytes = abi.encodePacked(address(sdMavOftEth));
    bytes sdMavOftBaseBytes = abi.encodePacked(address(sdMavOftBase));
    bytes sdMavOftBnbBytes = abi.encodePacked(address(sdMavOftBnb));
    bytes sdMavOftZkSyncBytes = abi.encodePacked(address(sdMavOftZkSync));

    string rpcAlias;

    constructor(string memory _rpcAlias) {
        rpcAlias = _rpcAlias;
    }

    function run() public {
        uint256 forkId = vm.createFork(vm.rpcUrl(rpcAlias));
        vm.selectFork(forkId);
        vm.startBroadcast(deployer);
        bytes32 rpcAliasHash = keccak256(abi.encodePacked((rpcAlias)));
        
        if (keccak256(abi.encodePacked("ethereum")) == rpcAliasHash) {
            sdMavOftEth.setTrustedRemoteAddress(184, sdMavOftBaseBytes);
            sdMavOftEth.setTrustedRemoteAddress(102, sdMavOftBnbBytes);
            sdMavOftEth.setTrustedRemoteAddress(165, sdMavOftZkSyncBytes);
        }
        if (keccak256(abi.encodePacked("base")) == rpcAliasHash) {
            sdMavOftBase.setTrustedRemoteAddress(101, sdMavOftEthBytes);
            sdMavOftBase.setTrustedRemoteAddress(102, sdMavOftBnbBytes);
            sdMavOftBase.setTrustedRemoteAddress(165, sdMavOftZkSyncBytes);
        }
        if (keccak256(abi.encodePacked("bnb")) == rpcAliasHash) {
            sdMavOftBnb.setTrustedRemoteAddress(184, sdMavOftBaseBytes);
            sdMavOftBnb.setTrustedRemoteAddress(101, sdMavOftEthBytes);
            sdMavOftBnb.setTrustedRemoteAddress(165, sdMavOftZkSyncBytes);
        }
        if (keccak256(abi.encodePacked("zkSync")) == rpcAliasHash) {
            sdMavOftZkSync.setTrustedRemoteAddress(184, sdMavOftBaseBytes);
            sdMavOftZkSync.setTrustedRemoteAddress(102, sdMavOftBnbBytes);
            sdMavOftZkSync.setTrustedRemoteAddress(101, sdMavOftEthBytes);
        }
        vm.stopBroadcast();
    }
}

contract SetTrustedRemoteOfEthereum is SetTrustedRemoteOft("ethereum") {}
contract SetTrustedRemoteOfBase is SetTrustedRemoteOft("base") {}
contract SetTrustedRemoteBnb is SetTrustedRemoteOft("bnb") {}
contract SetTrustedRemoteZkSync is SetTrustedRemoteOft("zkSync") {}