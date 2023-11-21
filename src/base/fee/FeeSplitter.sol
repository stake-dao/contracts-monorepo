// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IAccumulator} from "src/base/interfaces/IAccumulator.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @title A contract that receive token at every strategy harvest
/// @author StakeDAO
contract FeeSplitter {

    /// @notice accumulator
    address public accumulator;

    /// @notice governance
    address public governance;

    /// @notice future governance
    address public futureGovernance;

    /// @notice throwed when the msg.sender is not the futureGovernance
    error FUTURE_GOV();

    /// @notice throwed when the msg.sender is not the governance
    error GOV();

    /// @notice throwed when the address set is address(0)
    error ZERO_ADDRESS();

    /// @notice Emitted when the accumulator is set
    event AccumulatorSet(address _accumulator);

    /// @notice Emitted when the future governance is set
    event TransferGovernance(address _futureGovernance);

    /// @notice Emitted when the future governance accept it
    event GovernanceAccepted(address _governance);

    modifier onlyGov {
        if (msg.sender != governance) revert GOV();
        _;
    }

    modifier onlyFutureGov {
        if (msg.sender != futureGovernance) revert FUTURE_GOV();
        _;
    }

    constructor(address _accumulator) {
        accumulator = _accumulator;
    }

    /// @notice Transfers a token to a recipient
    /// @dev Can be called only by the governance
    /// @param _token token to transfer
    /// @param _amount amount to transfer
    /// @param _recipient recipient address
    function transferTokenToRecipient(address _token, uint256 _amount, address _recipient) external onlyGov {
        ERC20(_token).transfer(_recipient, _amount);
    }

    /// @notice Transfers a token to different recipients 
    /// @dev Can be called only by the governance
    /// @param _token token to transfer
    /// @param _amounts amount to transfer
    /// @param _recipients recipients addresses
    function transferTokenToRecipients(address _token, uint256[] memory _amounts, address[] memory _recipients) external onlyGov {
        uint256 length = _amounts.length;
        for (uint256 i; i < length;) {
            ERC20(_token).transfer(_recipients[i], _amounts[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Transfers tokens to a recipient
    /// @dev Can be called only by the governance
    /// @param _tokens tokens to transfer
    /// @param _amounts amount to transfer
    /// @param _recipient recipient address
    function transferTokensToRecipient(address[] memory _tokens, uint256[] memory _amounts, address _recipient) external onlyGov {
        uint256 length = _tokens.length;
        for (uint256 i; i < length;) {
            ERC20(_tokens[i]).transfer(_recipient, _amounts[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Transfers tokens to different recipients 
    /// @dev Can be called only by the governance
    /// @param _tokens tokens to transfer
    /// @param _amounts amount to to transfer
    /// @param _recipients recipients 
    function transferTokensToRecipients(address[] memory _tokens, uint256[] memory _amounts, address[] memory _recipients) external onlyGov {
        uint256 length = _tokens.length;
        for (uint256 i; i < length;) {
            ERC20(_tokens[i]).transfer(_recipients[i], _amounts[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @notice Set a token to the accumulator
    /// @dev Can be called only by the governance
    /// @param _token token to deposit
    /// @param _amount amount to deposit
    function depositTokenToAccumulator(address _token, uint256 _amount) external onlyGov {
        SafeTransferLib.safeApprove(_token, accumulator, _amount);
        // transfer tokens to the acc without charging fees on them when the rewatd is notified
        IAccumulator(accumulator).depositTokenWithoutChargingFee(_token, _amount);
    }

    /// @notice Set a new future governance that can accept it
    /// @dev Can be called only by the governance
    /// @param _futureGovernance future governance address
    function transferGovernance(address _futureGovernance) external onlyGov {
        if (_futureGovernance == address(0)) revert ZERO_ADDRESS();
        emit TransferGovernance(futureGovernance = _futureGovernance);
    }

    /// @notice Accept the governance
    /// @dev Can be called only by future governance
    function acceptGovernance() external onlyFutureGov {
        emit GovernanceAccepted(governance = futureGovernance);
    }

    /// @notice Set an accumulator
    /// @dev Can be called only by the governance
    function setAccumulator(address _accumulator) external onlyGov {
        emit AccumulatorSet(accumulator = _accumulator);
    }
}