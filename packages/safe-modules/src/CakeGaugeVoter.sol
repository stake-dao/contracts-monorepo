// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {AllowanceManager} from "./governance/AllowanceManager.sol";
import {ISafe} from "./interfaces/ISafe.sol";
import {ISafeOperation} from "./interfaces/ISafeOperation.sol";
import {DAO} from "address-book/src/DAOEthereum.sol";
import {PancakeswapLocker} from "address-book/src/PancakeswapBSC.sol";

contract CakeGaugeVoter is AllowanceManager {
    /// @notice Stake DAO governance owner
    address public immutable SD_SAFE = address(DAO.GOVERNANCE);
    address public immutable VOTER = address(PancakeswapLocker.VOTER);

    constructor() AllowanceManager(msg.sender) {}

    /// @notice Bundle gauge votes, _gauges and _weights must have the same length
    /// @param _gauges Array of gauge addresses
    /// @param _weights Array of weights
    function vote(address[] calldata _gauges, uint256[] calldata _weights, uint256[] calldata _chainIds)
        external
        onlyGovernanceOrAllowed
    {
        if (_gauges.length != _weights.length || _gauges.length != _chainIds.length) {
            revert WRONG_DATA();
        }

        bytes memory data = abi.encodeWithSignature(
            "voteForGaugeWeightsBulk(address[],uint256[],uint256[],bool,bool)",
            _gauges,
            _weights,
            _chainIds,
            false,
            false
        );
        require(ISafe(SD_SAFE).execTransactionFromModule(VOTER, 0, data, ISafeOperation.Call), "Could not execute vote");
    }

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when we try to vote with gauges length different than weights length
    error WRONG_DATA();
}
