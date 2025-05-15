// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {Enum} from "@safe/contracts/common/Enum.sol";
import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";
import {Safe} from "@safe/contracts/Safe.sol";
import {ILocker, ISafe} from "src/common/interfaces/zerolend/stakedao/ILocker.sol";
import {Common} from "address-book/src/CommonEthereum.sol";

/// @title SafeProxyFactoryLibrary
/// @notice This library is used to deploy a Safe proxy contract.
/// @custom:contact contact@stakedao.org
library SafeProxyFactoryLibrary {
    SafeProxyFactory internal constant SAFE_PROXY_FACTORY = SafeProxyFactory(Common.SAFE_PROXY_FACTORY);
    address internal constant SAFE_SINGLETON = Common.SAFE_SINGLETON;

    function _getSafeInitializationData(address[] memory owners, uint256 threshold)
        private
        pure
        returns (bytes memory initializer)
    {
        initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,
            threshold,
            address(0), // Contract address for optional delegate call.
            abi.encodePacked(), // Data payload for optional delegate call.
            address(0), // Handler for fallback calls to this contract
            address(0), // Token that should be used for the payment (0 is ETH)
            address(0), // Value that should be paid
            address(0) // Address that should receive the payment (or 0 if tx.origin)
        );
    }

    function deploy(uint256 salt, address[] memory owners, uint256 threshold) internal returns (address safe) {
        bytes memory initializer = _getSafeInitializationData(owners, threshold);
        safe = address(SAFE_PROXY_FACTORY.createProxyWithNonce(SAFE_SINGLETON, initializer, salt));
    }

    function deploy(uint256 salt, address[] memory owners) internal returns (address) {
        return deploy(salt, owners, 1);
    }

    function safeEnableModule(address locker, address module, bytes memory signature) internal {
        ILocker(locker).execTransaction(
            locker,
            0,
            abi.encodeWithSelector(ISafe.enableModule.selector, module),
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signature
        );
    }
}
