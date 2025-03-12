// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./governance/AllowanceManager.sol";
import "./interfaces/ISafe.sol";
import "./interfaces/ISafeOperation.sol";

contract CakeGaugeVoter is AllowanceManager {

    /// @notice Stake DAO governance owner
    address public immutable SD_SAFE = address(0xB0552b6860CE5C0202976Db056b5e3Cc4f9CC765);
    address public immutable VOTER = address(0x3c7b193aa39a85FDE911465d35CE3A74499F0A7B);

    constructor() AllowanceManager(msg.sender) {

    }

    /// @notice Bundle gauge votes, _gauges and _weights must have the same length
    /// @param _gauges Array of gauge addresses
    /// @param _weights Array of weights
    function vote(address[] calldata _gauges, uint256[] calldata _weights, uint256[] calldata _chainIds) external onlyGovernanceOrAllowed {
        if(_gauges.length != _weights.length || _gauges.length != _chainIds.length) {
            revert WRONG_DATA();
        }

        bytes memory data = abi.encodeWithSignature("voteForGaugeWeightsBulk(address[],uint256[],uint256[],bool,bool)", _gauges, _weights, _chainIds, false, false);
        require(ISafe(SD_SAFE).execTransactionFromModule(VOTER, 0, data, ISafeOperation.Call), "Could not execute vote");
    }

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when we try to vote with gauges length different than weights length
    error WRONG_DATA();
}