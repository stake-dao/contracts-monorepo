// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Common} from "address-book/src/CommonEthereum.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";
import {SpectraLocker as SpectraLockerBase} from "address-book/src/SpectraBase.sol";
import {SpectraLocker} from "address-book/src/SpectraEthereum.sol";
import {Script} from "forge-std/src/Script.sol";
import {APWine2SpectraConverter} from "src/base/spectra/APWine2SpectraConverter.sol";

interface ICreate3Factory {
    function deployCreate3(bytes32 salt, bytes memory code) external returns (address);
}

contract Deploy is Script {
    address public constant laPoste = DAO.LAPOSTE;
    address public constant CREATE3_FACTORY = Common.CREATE3_FACTORY;

    bytes32 public salt = keccak256(abi.encodePacked("SdapwineSdspectraConverter"));

    function run() public {
        vm.createSelectFork("mainnet");
        bytes memory converterInitCode = abi.encodePacked(
            type(APWine2SpectraConverter).creationCode,
            abi.encode(SpectraLocker.SDTOKEN, SpectraLocker.GAUGE, laPoste, 8453, 0)
        );
        vm.broadcast();
        address converterMainnet = ICreate3Factory(CREATE3_FACTORY).deployCreate3(salt, converterInitCode);

        vm.createSelectFork("base");
        converterInitCode = abi.encodePacked(
            type(APWine2SpectraConverter).creationCode,
            abi.encode(SpectraLockerBase.SDTOKEN, SpectraLockerBase.GAUGE, laPoste, 0, 20 ether)
        );
        vm.broadcast();
        address converterBase = ICreate3Factory(CREATE3_FACTORY).deployCreate3(salt, converterInitCode);

        require(converterMainnet == converterBase);
    }
}
