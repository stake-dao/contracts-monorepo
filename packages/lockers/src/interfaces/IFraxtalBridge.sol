// SPDX-License-Identifier: BUSL-1.1
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
