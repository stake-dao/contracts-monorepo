// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "src/common/interfaces/IOptimismMintableERC20.sol";
import {ISdToken} from "src/common/interfaces/ISdToken.sol";
import "src/fraxtal/FXTLDelegation.sol";

/// @title sdTokenOperator
/// @author StakeDAO
/// @notice A middleware contract used to allow multi addresses to mint/burn sdToken, it needs to be the sdToken's operator
contract sdTokenOperator is IOptimismMintableERC20, FXTLDelegation {
    /// @notice Address of the remote token in ethereum
    address public immutable remoteToken;

    /// @notice Address of the bridge in fraxtal
    address public immutable bridge;

    /// @notice Address of the governance
    address public governance;

    /// @notice Address of the future governance
    address public futureGovernance;

    /// @notice sdToken
    ISdToken public immutable sdToken;

    /// @notice address -> enabled or not
    mapping(address => bool) public operators;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    ///////////////////////////////////////////////////////////////

    /// @notice Throwed when an operator has already allowed
    error AlreadyAllowed();

    /// @notice Throwed when an operator has not allowed
    error NotAllowed();

    /// @notice Throwed at Auth
    error Auth();

    /// @notice Emitted when the governance changes
    event GovernanceChanged(address governance);

    /// @notice Emitted when an operator is allowed
    event OperatorAllowed(address operator);

    /// @notice Emitted when an operator is disallowed
    event OperatorDisallowed(address operator);

    modifier onlyFutureGovernance() {
        if (msg.sender != futureGovernance) revert Auth();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert Auth();
        _;
    }

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert Auth();
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Constructor
    /// @param _sdToken Address of the sdToken
    /// @param _governance Address of the governance
    /// @param _remoteToken Address of the remote sdToken
    /// @param _bridge Address of the frax bridge
    /// @param _delegationRegistry Address of the fraxtal delegation registry
    /// @param _initialDelegate Address of the delegate that receives network reward
    constructor(
        address _sdToken,
        address _governance,
        address _remoteToken,
        address _bridge,
        address _delegationRegistry,
        address _initialDelegate
    ) FXTLDelegation(_delegationRegistry, _initialDelegate) {
        sdToken = ISdToken(_sdToken);
        governance = _governance;
        remoteToken = _remoteToken;
        bridge = _bridge;
    }

    /// @notice mint new sdToken, callable only by the operator
    /// @param _to recipient to mint for
    /// @param _amount amount to mint
    function mint(address _to, uint256 _amount) external onlyOperator {
        sdToken.mint(_to, _amount);
    }

    /// @notice burn sdToken, callable only by the operator
    /// @param _from sdToken holder
    /// @param _amount amount to burn
    function burn(address _from, uint256 _amount) external onlyOperator {
        sdToken.burn(_from, _amount);
    }

    /// @notice Allow a new operator that can mint and burn sdToken
    /// @param _operator new operator address
    function allowOperator(address _operator) external onlyGovernance {
        if (operators[_operator]) revert AlreadyAllowed();
        operators[_operator] = true;

        emit OperatorAllowed(_operator);
    }

    /// @notice Allow a new operator that can mint and burn sdToken
    /// @param _operator new operator address
    function disallowOperator(address _operator) external onlyGovernance {
        if (!operators[_operator]) revert NotAllowed();
        operators[_operator] = false;

        emit OperatorDisallowed(_operator);
    }

    /// @notice Set a new sdToken's operator, after this action the contract can't mint/burn
    /// @param _operator new operator address
    function setSdTokenOperator(address _operator) external onlyGovernance {
        sdToken.setOperator(_operator);
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external onlyFutureGovernance {
        governance = msg.sender;
        futureGovernance = address(0);
        emit GovernanceChanged(msg.sender);
    }

    /// @notice ERC165 interface check function.
    /// @param _interfaceId Interface ID to check.
    /// @return Whether or not the interface is supported by this contract.
    function supportsInterface(bytes4 _interfaceId) external pure virtual returns (bool) {
        bytes4 iface1 = type(IERC165).interfaceId;
        // Interface corresponding to the updated OptimismMintableERC20 (this contract).
        bytes4 iface2 = type(IOptimismMintableERC20).interfaceId;
        return _interfaceId == iface1 || _interfaceId == iface2;
    }
}
