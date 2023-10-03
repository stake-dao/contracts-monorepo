// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {sdMAV} from "src/mav/token/sdMAV.sol";

address constant LZ_ENDPOINT_ETH = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
address constant LZ_ENDPOINT_BASE = 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;
address constant LZ_ENDPOINT_BNB = 0x3c2269811836af69497E5F486A85D7316753cf62;
address constant LZ_ENDPOINT_ZKSYNC = 0x9b896c0e23220469C7AE69cb4BbAE391eAa4C8da;

abstract contract DeploySdMAVOft is Script, Test {
    address public deployer = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;

    address public lzEndpoint;
    string public rpcAlias;

    sdMAV sdMav;

    constructor(address _lzEndpoint, string memory _rpcAlias) {
        lzEndpoint = _lzEndpoint;
        rpcAlias = _rpcAlias;
    }

    function run() public {
        uint256 forkId = vm.createFork(vm.rpcUrl(rpcAlias));
        vm.selectFork(forkId);
        vm.startBroadcast(deployer);
        string memory tokenName = "Stake DAO MAV";
        string memory tokenSymbol = "sdMAV";
        sdMav = new sdMAV(tokenName, tokenSymbol, lzEndpoint);
        vm.stopBroadcast();
    }
}

contract DeploySdMAVOftEth is DeploySdMAVOft(LZ_ENDPOINT_ETH, "ethereum") {}

contract DeploySdMAVOftBase is DeploySdMAVOft(LZ_ENDPOINT_BASE, "base") {}

contract DeploySdMAVOftBnb is DeploySdMAVOft(LZ_ENDPOINT_BNB, "bnb") {}

contract DeploySdMAVOftZkSync is DeploySdMAVOft(LZ_ENDPOINT_ZKSYNC, "zkSync") {}
