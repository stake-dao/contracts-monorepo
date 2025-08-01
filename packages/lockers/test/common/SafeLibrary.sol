/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";
import {Safe, Enum} from "@safe/contracts/Safe.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";

library SafeLibrary {
    /// @notice Safe proxy factory address. Same address on all chains.
    SafeProxyFactory public constant SAFE_PROXY_FACTORY = SafeProxyFactory(Common.SAFE_PROXY_FACTORY);

    /// @notice Safe singleton address. Same address on all chains.
    address public constant SAFE_SINGLETON = Common.SAFE_SINGLETON;

    /// @notice Fallback handler address. Same address on all chains.
    address public constant FALLBACK_HANDLER = Common.SAFE_FALLBACK_HANDLER;

    function deploySafe(address[] memory _owners, uint256 _threshold, uint256 _saltNonce) public returns (Safe) {
        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            _owners, // Owners.
            _threshold, // Threshold. How many owners to confirm a transaction.
            address(0), // Optional Safe account if already deployed.
            abi.encodePacked(), // Optional data.
            address(FALLBACK_HANDLER), // Fallback handler.
            address(0), // Optional payment token.
            0, // Optional payment token amount.
            address(0) // Optional payment receiver.
        );

        return Safe(
            payable(
                SAFE_PROXY_FACTORY.createProxyWithNonce({
                    _singleton: SAFE_SINGLETON,
                    initializer: initializer,
                    saltNonce: _saltNonce
                })
            )
        );
    }

    /// @notice Simple function to execute a transaction on a Safe.
    /// @param _safe The address of the Safe.
    /// @param _target The address of the target contract.
    /// @param _data The data to execute on the target contract.
    function simpleExec(address payable _safe, address _target, bytes memory _data, bytes memory _signatures)
        internal
        returns (bool)
    {
        return Safe(_safe).execTransaction({
            to: _target,
            value: 0,
            data: _data,
            operation: Enum.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(0),
            signatures: _signatures
        });
    }
}
