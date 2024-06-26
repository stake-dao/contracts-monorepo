// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IBatchFactory {
    function deploy(address _gauge) external returns (address _adapter);
    function create(address _gauge) external returns (address vault, address rewardDistributor);
}

/// @notice Helper contract to deploy new vaults and adapters in a single transaction.
contract BatchFactory {
    /// @notice Pancake factory address.
    address public immutable factory;

    /// @notice Pancake adapter factory address.
    address public immutable adapterFactory;

    constructor(address _factory, address _adapterFactory) {
        factory = _factory;
        adapterFactory = _adapterFactory;
    }

    /// @notice Deploy a new vault and adapter for the given gauge.
    /// @param _gauge Address of the gauge to deploy the vault and adapter for.
    function deploy(address _gauge, bool deployAdapter)
        external
        returns (address _vault, address _rewardDistributor, address _adapter)
    {
        (_vault, _rewardDistributor) = IBatchFactory(factory).create(_gauge);

        if (deployAdapter) {
            _adapter = IBatchFactory(adapterFactory).deploy(_gauge);
        }
    }
}
