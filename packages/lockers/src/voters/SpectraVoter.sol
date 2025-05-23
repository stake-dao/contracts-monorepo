// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {BaseVoter} from "src/voters/BaseVoter.sol";
import {SpectraProtocol, SpectraLocker} from "address-book/src/SpectraBase.sol";
import {ISpectraVoter} from "src/common/interfaces/ISpectraVoter.sol";

contract SpectraVoter is BaseVoter {
    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    address public immutable LOCKER = SpectraLocker.LOCKER;
    address public immutable VOTER = SpectraProtocol.VOTER;
    address public immutable VE_SPECTRA = SpectraProtocol.VESPECTRA;
    uint256 public immutable TOKEN_ID = 1263;

    constructor(address _gateway) BaseVoter(_gateway) {}

    /// @notice Bundle gauge votes
    /// @param _poolVotes Array of pool ids
    /// @param _weights Array of weights
    /// @dev The `_gauges` and `_weights` parameters must have the same length
    /// @custom:throws INCORRECT_LENGTH if the `_gauges` and `_weights` parameters have different lengths
    function voteGauges(uint160[] calldata _poolVotes, uint256[] calldata _weights) external hasGaugesOrAllPermission {
        if (_poolVotes.length != _weights.length) revert INCORRECT_LENGTH();

        bytes memory data =
            abi.encodeWithSelector(ISpectraVoter.vote.selector, VE_SPECTRA, TOKEN_ID, _poolVotes, _weights);
        _executeTransaction(VOTER, data);
    }

    /// @notice DEPRECATED: Use `voteGauges(uint160[],uint256[])` instead
    function voteGauges(address[] calldata, uint256[] calldata) external virtual override {
        revert("NOT_IMPLEMENTED");
    }

    ////////////////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////

    /// @notice Get the locker address
    /// @dev Must be implemented for the SafeModule contract
    function _getLocker() internal view override returns (address) {
        return LOCKER;
    }

    function _getController() internal pure override returns (address) {
        revert("NOT_IMPLEMENTED");
    }
}
