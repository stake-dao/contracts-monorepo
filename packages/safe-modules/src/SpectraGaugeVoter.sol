// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./governance/AllowanceManager.sol";
import "./interfaces/ISafe.sol";
import "./interfaces/ISafeOperation.sol";

contract SpectraGaugeVoter is AllowanceManager {

    /// @notice Stake DAO governance owner
    address public immutable SD_SAFE = address(0xC0295F271c4fD531d436F55b0ceF4Cc316188046);
    address public immutable VOTER = address(0x174a1f4135Fab6e7B6Dbe207fF557DFF14799D33);
    address public immutable VE_SPECTRA = address(0x6a89228055C7C28430692E342F149f37462B478B);
    uint256 public immutable TOKEN_ID = 1263;

    constructor() AllowanceManager(msg.sender) {

    }

    /// @notice Bundle gauge votes
    /// @param _poolVotes Array of pool ids
    /// @param _weights Array of weights
    function vote(uint160[] calldata _poolVotes, uint256[] calldata _weights) external onlyGovernanceOrAllowed {
        if(_poolVotes.length != _weights.length) {
            revert WRONG_DATA();
        }

        bytes memory data = abi.encodeWithSignature("vote(address,uint256,uint160[],uint256[])", VE_SPECTRA, TOKEN_ID, _poolVotes, _weights);
        require(ISafe(SD_SAFE).execTransactionFromModule(VOTER, 0, data, ISafeOperation.Call), "Could not execute vote");
    }

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Error emitted when we try to vote with gauges length different than weights length
    error WRONG_DATA();
}