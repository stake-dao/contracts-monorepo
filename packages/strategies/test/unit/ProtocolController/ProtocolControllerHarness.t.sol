pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {ProtocolController} from "src/ProtocolController.sol";

// Exposes the useful internal functions of the Accountant contract for testing purposes
contract ProtocolControllerHarness is ProtocolController, Test {
    function _exposed_permissions(address _contract, address _caller, bytes4 _selector) external view returns (bool) {
        return _permissions[_contract][_caller][_selector];
    }

    function _cheat_override_protocol_components(bytes4 _protocolId, ProtocolComponents memory components) external {
        _protocolComponents[_protocolId] = components;
    }

    function _cheat_override_gauge(address gaugeAddress, Gauge memory gaugeData) external {
        gauge[gaugeAddress] = gaugeData;
    }

    function _cheat_override_permissions(address _contract, address _caller, bytes4 _selector, bool _allowed)
        external
    {
        _permissions[_contract][_caller][_selector] = _allowed;
    }
}
