// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "forge-std/src/Script.sol";
import "address-book/src/dao/1.sol";
import "address-book/src/lockers/8453.sol";
import {SPECTRA as APWINE} from "address-book/src/lockers/1.sol";
import {APWine2SpectraConverter} from "src/base/spectra/APWine2SpectraConverter.sol";

interface ICreate3Factory {
    function deployCreate3(bytes32 salt, bytes memory code) external returns (address);
}

contract Deploy is Script {
    address public constant laPoste = 0xF0000058000021003E4754dCA700C766DE7601C2;
    address public constant CREATE3_FACTORY = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    bytes32 public salt = keccak256(abi.encodePacked("SdapwineSdspectraConverter"));

    function run() public {
        vm.createSelectFork("mainnet");
        bytes memory converterInitCode = abi.encodePacked(
            type(APWine2SpectraConverter).creationCode, abi.encode(APWINE.SDTOKEN, APWINE.GAUGE, laPoste, 8453, 0)
        );
        vm.broadcast(DAO.MAIN_DEPLOYER);
        address converterMainnet = ICreate3Factory(CREATE3_FACTORY).deployCreate3(salt, converterInitCode);

        vm.createSelectFork("base");
        converterInitCode = abi.encodePacked(
            type(APWine2SpectraConverter).creationCode, abi.encode(SPECTRA.SDTOKEN, SPECTRA.GAUGE, laPoste, 0, 20 ether)
        );
        vm.broadcast(DAO.MAIN_DEPLOYER);
        address converterBase = ICreate3Factory(CREATE3_FACTORY).deployCreate3(salt, converterInitCode);

        require(converterMainnet == converterBase);
    }
}
