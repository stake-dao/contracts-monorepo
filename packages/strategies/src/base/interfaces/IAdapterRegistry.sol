// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface IAdapterRegistry {
    function setAdapter(address _vault, address _adapter) external;
    function getAdapter(address _vault) external view returns (address);
}
