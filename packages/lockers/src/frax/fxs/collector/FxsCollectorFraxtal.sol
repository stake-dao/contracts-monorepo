// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Collector} from "src/base/collector/Collector.sol";

/// @title A contract that collect FXS from users and mints sdFXS at 1:1 rate, later on, when the FXS depositor will be deployed
/// @dev To be used only on the Fraxtal chain (ad-hoc contructor to delegate the Fraxtal network's rewards).
/// @author StakeDAO
contract FxsCollectorFraxtal is Collector {
    /// @notice Constructor
    /// @param _governance Address of the governance
    /// @param _delegationRegistry Address of the Fraxtal's Frax Delegation registry used to delegate epoch reward
    /// @param _initialDelegate Address of the delegate reward contract that receives it at every epoch on fraxtal
    constructor(address _governance, address _delegationRegistry, address _initialDelegate)
        Collector(_governance, 0xFc00000000000000000000000000000000000002)
    {
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert CallFailed();
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert CallFailed();
    }

    function name() public pure override returns (string memory) {
        return "FXS Collector";
    }

    function symbol() public pure override returns (string memory) {
        return "FXSC";
    }
}
