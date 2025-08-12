// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PendleLocker} from "@address-book/src/PendleEthereum.sol";
import {IDepositor} from "src/interfaces/IDepositor.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IStandardizedYieldAdapter} from "@pendle/v2-sy/../interfaces/IStandardizedYieldAdapter.sol";

contract SYASDPENDLEAdapter is IStandardizedYieldAdapter {
    address public constant PIVOT_TOKEN = PendleLocker.SDTOKEN;

    constructor() {
        SafeTransferLib.safeApprove(PendleLocker.TOKEN, PendleLocker.DEPOSITOR, type(uint256).max);
    }

    ///////////////////////////////////////////////////////////////
    // --- DEPOSIT
    ///////////////////////////////////////////////////////////////

    function getAdapterTokensDeposit() external pure returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = PendleLocker.TOKEN;
    }

    function previewConvertToDeposit(address, /*tokenIn*/ uint256 amountIn) external pure returns (uint256) {
        return amountIn;
    }

    function convertToDeposit(address, /*tokenIn*/ uint256 amountTokenIn) external returns (uint256 amountOut) {
        IDepositor(PendleLocker.DEPOSITOR).deposit(amountTokenIn, true, false, msg.sender);
        amountOut = amountTokenIn;
    }

    ///////////////////////////////////////////////////////////////
    // --- REDEEM
    ///////////////////////////////////////////////////////////////

    function getAdapterTokensRedeem() external pure override returns (address[] memory tokens) {
        tokens = new address[](0);
    }

    function previewConvertToRedeem(address, /*tokenOut*/ uint256 /*amountIn*/ ) external pure returns (uint256) {
        return 0;
    }

    function convertToRedeem(address, /*tokenOut*/ uint256 /*amountYieldTokenIn*/ ) external pure returns (uint256) {
        revert("REDEEM_NOT_SUPPORTED");
    }
}
