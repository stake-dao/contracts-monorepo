// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

interface ISidecarFactory {
    function sidecar(address gauge) external view returns (address);
    function create(address token, bytes memory args) external returns (address);
}
