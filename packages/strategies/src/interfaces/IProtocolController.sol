/// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IProtocolController {
    function vault(address) external view returns (address);
    function asset(address) external view returns (address);
    function rewardReceiver(address) external view returns (address);

    function allowed(address, address, bytes4 selector) external view returns (bool);
    function permissionSetters(address) external view returns (bool);
    function isRegistrar(address) external view returns (bool);

    function strategy(bytes4 protocolId) external view returns (address);
    function allocator(bytes4 protocolId) external view returns (address);
    function accountant(bytes4 protocolId) external view returns (address);
    function feeReceiver(bytes4 protocolId) external view returns (address);
    function factory(bytes4 protocolId) external view returns (address);

    function isPaused(bytes4) external view returns (bool);
    function isShutdown(address) external view returns (bool);

    function registerVault(address _gauge, address _vault, address _asset, address _rewardReceiver, bytes4 _protocolId)
        external;

    function setValidAllocationTarget(address _gauge, address _target) external;
    function removeValidAllocationTarget(address _gauge, address _target) external;
    function isValidAllocationTarget(address _gauge, address _target) external view returns (bool);

    function shutdown(address _gauge) external;

    function setPermissionSetter(address _setter, bool _allowed) external;
    function setPermission(address _contract, address _caller, bytes4 _selector, bool _allowed) external;
}
