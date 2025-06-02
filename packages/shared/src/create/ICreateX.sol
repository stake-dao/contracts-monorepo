// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface ICreateX {
    // Structs
    struct Values {
        uint256 constructorAmount;
        uint256 initCallAmount;
    }

    // CREATE3
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
    function deployCreate3(bytes memory initCode) external payable returns (address newContract);
    function deployCreate3AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    ) external payable returns (address newContract);
    function deployCreate3AndInit(bytes32 salt, bytes memory initCode, bytes memory data, Values memory values)
        external
        payable
        returns (address newContract);
    function deployCreate3AndInit(bytes memory initCode, bytes memory data, Values memory values, address refundAddress)
        external
        payable
        returns (address newContract);
    function deployCreate3AndInit(bytes memory initCode, bytes memory data, Values memory values)
        external
        payable
        returns (address newContract);
    function computeCreate3Address(bytes32 salt, address deployer) external pure returns (address computedAddress);
    function computeCreate3Address(bytes32 salt) external view returns (address computedAddress);
}
