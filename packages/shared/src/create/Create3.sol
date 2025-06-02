/// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {CommonUniversal} from "address-book/src/CommonUniversal.sol";
import {ICreateX} from "src/create/ICreateX.sol";

/// @title Create3 Library
/// @dev This library interacts with pcaversaccio's CREATEX Factory to deploy contracts via the CREATE3 pattern.
/// @custom:url https://github.com/pcaversaccio/createx
/// @custom:contact contact@stakedao.org
library Create3 {
    ICreateX internal constant CREATEX_FACTORY = ICreateX(CommonUniversal.CREATE3_FACTORY);

    /// @dev Deploys a new contract via employing the `CREATE3` pattern (i.e. without an initcode
    /// factor) and using the salt value `salt`, the creation bytecode `initCode`, and `msg.value`
    /// as inputs. In order to save deployment costs, we do not sanity check the `initCode` length.
    /// Note that if `msg.value` is non-zero, `initCode` must have a `payable` constructor. This
    /// implementation is based on Solmate.
    /// @param salt The 32-byte random value used to create the proxy contract address.
    /// @param initCode The creation bytecode.
    /// @param value The amount of ether to send to the contract.
    /// @return newContract The 20-byte address where the contract was deployed.
    /// @custom:security We strongly recommend implementing a permissioned deploy protection by setting
    /// the first 20 bytes equal to `msg.sender` in the `salt` to prevent maliciously intended frontrun
    /// proxy deployments on other chains.
    function deployCreate3(bytes32 salt, bytes memory initCode, uint256 value) internal returns (address newContract) {
        newContract = CREATEX_FACTORY.deployCreate3{value: value}(salt, initCode);
    }

    /// @dev Deploys a new contract via employing the `CREATE3` pattern (i.e. without an initcode
    /// factor) and using the salt value `salt`, the creation bytecode `initCode`, and `msg.value`
    /// as inputs. In order to save deployment costs, we do not sanity check the `initCode` length.
    /// Note that if `msg.value` is non-zero, `initCode` must have a `payable` constructor. This
    /// implementation is based on Solmate.
    /// @param salt The 32-byte random value used to create the proxy contract address.
    /// @param initCode The creation bytecode.
    /// @return newContract The 20-byte address where the contract was deployed.
    /// @custom:security We strongly recommend implementing a permissioned deploy protection by setting
    /// the first 20 bytes equal to `msg.sender` in the `salt` to prevent maliciously intended frontrun
    /// proxy deployments on other chains.
    function deployCreate3(bytes32 salt, bytes memory initCode) internal returns (address newContract) {
        newContract = CREATEX_FACTORY.deployCreate3(salt, initCode);
    }

    /// @dev Deploys a new contract via employing the `CREATE3` pattern (i.e. without an initcode
    /// factor) and using the salt value `salt`, the creation bytecode `initCode`, and `msg.value`
    /// as inputs. The salt value is calculated pseudo-randomly using a diverse selection of block
    /// and transaction properties. This approach does not guarantee true randomness! In order to save
    /// deployment costs, we do not sanity check the `initCode` length. Note that if `msg.value` is
    /// non-zero, `initCode` must have a `payable` constructor. This implementation is based on Solmate.
    /// @param initCode The creation bytecode.
    /// @return newContract The 20-byte address where the contract was deployed.
    function deployCreate3(bytes memory initCode) internal returns (address newContract) {
        newContract = CREATEX_FACTORY.deployCreate3(initCode);
    }

    /// @dev Deploys and initialises a new contract via employing the `CREATE3` pattern (i.e. without
    /// an initcode factor) and using the salt value `salt`, the creation bytecode `initCode`, the
    /// initialisation code `data`, the struct for the `payable` amounts `values`, the refund address
    /// `refundAddress`, and `msg.value` as inputs. In order to save deployment costs, we do not sanity
    /// check the `initCode` length. Note that if `values.constructorAmount` is non-zero, `initCode` must
    /// have a `payable` constructor. This implementation is based on Solmate.
    /// @param salt The 32-byte random value used to create the proxy contract address.
    /// @param initCode The creation bytecode.
    /// @param data The initialisation code that is passed to the deployed contract.
    /// @param values The specific `payable` amounts for the deployment and initialisation call.
    /// @param refundAddress The 20-byte address where any excess ether is returned to.
    /// @return newContract The 20-byte address where the contract was deployed.
    /// @custom:security This function allows for reentrancy, however we refrain from adding
    /// a mutex lock to keep it as use-case agnostic as possible. Please ensure at the protocol
    /// level that potentially malicious reentrant calls do not affect your smart contract system.
    /// Furthermore, we strongly recommend implementing a permissioned deploy protection by setting
    /// the first 20 bytes equal to `msg.sender` in the `salt` to prevent maliciously intended frontrun
    /// proxy deployments on other chains.
    function deployCreate3AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        ICreateX.Values memory values,
        address refundAddress
    ) internal returns (address newContract) {
        newContract = CREATEX_FACTORY.deployCreate3AndInit(salt, initCode, data, values, refundAddress);
    }

    /// @dev Deploys and initialises a new contract via employing the `CREATE3` pattern (i.e. without
    /// an initcode factor) and using the salt value `salt`, the creation bytecode `initCode`, the
    /// initialisation code `data`, the struct for the `payable` amounts `values`, and `msg.value` as
    /// inputs. In order to save deployment costs, we do not sanity check the `initCode` length. Note
    /// that if `values.constructorAmount` is non-zero, `initCode` must have a `payable` constructor,
    /// and any excess ether is returned to `msg.sender`. This implementation is based on Solmate.
    /// @param salt The 32-byte random value used to create the proxy contract address.
    /// @param initCode The creation bytecode.
    /// @param data The initialisation code that is passed to the deployed contract.
    /// @param values The specific `payable` amounts for the deployment and initialisation call.
    /// @return newContract The 20-byte address where the contract was deployed.
    /// @custom:security This function allows for reentrancy, however we refrain from adding
    /// a mutex lock to keep it as use-case agnostic as possible. Please ensure at the protocol
    /// level that potentially malicious reentrant calls do not affect your smart contract system.
    /// Furthermore, we strongly recommend implementing a permissioned deploy protection by setting
    /// the first 20 bytes equal to `msg.sender` in the `salt` to prevent maliciously intended frontrun
    /// proxy deployments on other chains.
    function deployCreate3AndInit(bytes32 salt, bytes memory initCode, bytes memory data, ICreateX.Values memory values)
        internal
        returns (address newContract)
    {
        newContract = CREATEX_FACTORY.deployCreate3AndInit(salt, initCode, data, values);
    }

    /// @dev Deploys and initialises a new contract via employing the `CREATE3` pattern (i.e. without
    /// an initcode factor) and using the creation bytecode `initCode`, the initialisation code `data`,
    /// the struct for the `payable` amounts `values`, the refund address `refundAddress`, and `msg.value`
    /// as inputs. The salt value is calculated pseudo-randomly using a diverse selection of block and
    /// transaction properties. This approach does not guarantee true randomness! In order to save deployment
    /// costs, we do not sanity check the `initCode` length. Note that if `values.constructorAmount` is non-zero,
    /// `initCode` must have a `payable` constructor. This implementation is based on Solmate.
    /// @param initCode The creation bytecode.
    /// @param data The initialisation code that is passed to the deployed contract.
    /// @param values The specific `payable` amounts for the deployment and initialisation call.
    /// @param refundAddress The 20-byte address where any excess ether is returned to.
    /// @return newContract The 20-byte address where the contract was deployed.
    /// @custom:security This function allows for reentrancy, however we refrain from adding
    /// a mutex lock to keep it as use-case agnostic as possible. Please ensure at the protocol
    /// level that potentially malicious reentrant calls do not affect your smart contract system.
    function deployCreate3AndInit(
        bytes memory initCode,
        bytes memory data,
        ICreateX.Values memory values,
        address refundAddress
    ) internal returns (address newContract) {
        newContract = CREATEX_FACTORY.deployCreate3AndInit(initCode, data, values, refundAddress);
    }

    /// @dev Deploys and initialises a new contract via employing the `CREATE3` pattern (i.e. without
    /// an initcode factor) and using the creation bytecode `initCode`, the initialisation code `data`,
    /// the struct for the `payable` amounts `values`, `msg.value` as inputs. The salt value is calculated
    /// pseudo-randomly using a diverse selection of block and transaction properties. This approach does
    /// not guarantee true randomness! In order to save deployment costs, we do not sanity check the `initCode`
    /// length. Note that if `values.constructorAmount` is non-zero, `initCode` must have a `payable` constructor,
    /// and any excess ether is returned to `msg.sender`. This implementation is based on Solmate.
    /// @param initCode The creation bytecode.
    /// @param data The initialisation code that is passed to the deployed contract.
    /// @param values The specific `payable` amounts for the deployment and initialisation call.
    /// @return newContract The 20-byte address where the contract was deployed.
    /// @custom:security This function allows for reentrancy, however we refrain from adding
    /// a mutex lock to keep it as use-case agnostic as possible. Please ensure at the protocol
    /// level that potentially malicious reentrant calls do not affect your smart contract system.
    function deployCreate3AndInit(bytes memory initCode, bytes memory data, ICreateX.Values memory values)
        internal
        returns (address newContract)
    {
        newContract = CREATEX_FACTORY.deployCreate3AndInit(initCode, data, values);
    }

    /// @dev Returns the address where a contract will be stored if deployed via `deployer` using
    /// the `CREATE3` pattern (i.e. without an initcode factor). Any change in the `salt` value will
    /// result in a new destination address. This implementation is based on Solady.
    /// @param salt The 32-byte random value used to create the proxy contract address.
    /// @param deployer The 20-byte deployer address.
    /// @return computedAddress The 20-byte address where a contract will be stored.
    function computeCreate3Address(bytes32 salt, address deployer) internal pure returns (address computedAddress) {
        computedAddress = CREATEX_FACTORY.computeCreate3Address(salt, deployer);
    }

    /// @dev Returns the address where a contract will be stored if deployed via this contract using
    /// the `CREATE3` pattern (i.e. without an initcode factor). Any change in the `salt` value will
    /// result in a new destination address. This implementation is based on Solady.
    /// @param salt The 32-byte random value used to create the proxy contract address.
    /// @return computedAddress The 20-byte address where a contract will be stored.
    function computeCreate3Address(bytes32 salt) internal view returns (address computedAddress) {
        computedAddress = CREATEX_FACTORY.computeCreate3Address(salt);
    }
}
