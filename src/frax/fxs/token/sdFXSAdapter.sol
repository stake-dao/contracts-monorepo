// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {OFTAdapter} from "LayerZero-v2/oft/OFTAdapter.sol";

/// @title sdFxsOftV2 Adapter
/// @author StakeDAO
/// @notice An adapter token used to wrap the token and to be OFT compatible
contract sdFXSAdapter is OFTAdapter {
    constructor(address _token, address _lzEndpoint, address _delegate) OFTAdapter(_token, _lzEndpoint, _delegate) {}
}
