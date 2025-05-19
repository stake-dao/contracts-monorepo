// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

interface IFraxtalBridge {
    function bridgeERC20(
        address localToken,
        address remoteToken,
        uint256 amount,
        uint32 minGasLimit,
        bytes memory extraData
    ) external;
}
