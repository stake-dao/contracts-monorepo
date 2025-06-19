/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Safe, Enum} from "@safe/contracts/Safe.sol";
import {Common} from "@address-book/src/CommonEthereum.sol";
import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";

library SafeLibrary {
    /// @notice Safe singleton address. Same address on all chains.
    address public constant SAFE_SINGLETON = Common.SAFE_SINGLETON;

    /// @notice Safe L2 singleton address. Same address on all chains.
    address public constant SAFE_L2_SINGLETON = Common.SAFE_L2_SINGLETON;

    /// @notice Fallback handler address. Same address on all chains.
    address public constant FALLBACK_HANDLER = Common.SAFE_FALLBACK_HANDLER;

    /// @notice Safe proxy factory address. Same address on all chains.
    SafeProxyFactory public constant SAFE_PROXY_FACTORY = SafeProxyFactory(Common.SAFE_PROXY_FACTORY);

    function deploySafe(address[] memory _owners, uint256 _threshold, uint256 _saltNonce) internal returns (Safe) {
        /// Get the initializer for the Safe.
        bytes memory initializer = getInitializer(_owners, _threshold);

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

    /// @notice Deploy a Safe on L2.
    /// @param _owners The owners of the Safe.
    /// @param _threshold The threshold of the Safe.
    /// @param _saltNonce The salt nonce for the Safe.
    function deploySafeL2(address[] memory _owners, uint256 _threshold, uint256 _saltNonce) internal returns (Safe) {
        /// Get the initializer for the Safe.
        bytes memory initializer = getInitializer(_owners, _threshold);

        return Safe(
            payable(
                SAFE_PROXY_FACTORY.createProxyWithNonce({
                    _singleton: SAFE_L2_SINGLETON,
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

    /// @notice Simple function to execute a transaction on a Safe.
    /// @param _safe The address of the Safe.
    /// @param _target The address of the target contract.
    /// @param _data The data to execute on the target contract.
    function execOnLocker(
        address payable _safe,
        address _locker,
        address _target,
        bytes memory _data,
        bytes memory _signatures
    ) internal returns (bool) {
        _data = abi.encodeWithSignature("execute(address,uint256,bytes)", _target, 0, _data);

        return Safe(_safe).execTransaction({
            to: _locker,
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

    function getInitializer(address[] memory _owners, uint256 _threshold) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
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
    }
}
