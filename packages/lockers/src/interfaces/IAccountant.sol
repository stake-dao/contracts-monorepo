// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// @dev TODO: Move the IAccountant interface from the strategies package to the `interfaces`
//            package then import the shared interface directly.
interface IAccountant {
    function claimProtocolFees() external;
}
