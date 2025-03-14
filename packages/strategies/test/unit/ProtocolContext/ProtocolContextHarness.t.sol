// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ProtocolContext} from "src/ProtocolContext.sol";

contract ProtocolContextHarness is ProtocolContext {
    constructor(bytes4 protocolId, address protocolController, address locker, address gateway)
        ProtocolContext(protocolId, protocolController, locker, gateway)
    {}

    function _expose_executeTransaction(address target, bytes memory data) internal returns (bool success) {
        return _executeTransaction(target, data);
    }
}
