/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {SafeProxyFactory} from "@safe/contracts/proxies/SafeProxyFactory.sol";
import {Safe, Enum} from "@safe/contracts/Safe.sol";

library SafeLibrary {
    /// @notice Safe proxy factory address. Same address on all chains.
    SafeProxyFactory public constant SAFE_PROXY_FACTORY = SafeProxyFactory(0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67);

    /// @notice Safe singleton address. Same address on all chains.
    address public constant SAFE_SINGLETON = 0x41675C099F32341bf84BFc5382aF534df5C7461a;

    /// @notice Fallback handler address. Same address on all chains.
    address public constant FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;

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
