// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "src/base/interfaces/IOptimismMintableERC20.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

/// @title sdFxsFraxtal
/// @author StakeDAO
/// @notice A token that represents the Token deposited by a user into the Depositor
/// @dev Minting & Burning was modified to be used by the operator
contract sdFXSFraxtal is ERC20, IOptimismMintableERC20 {
    /// @notice Address of the remote token in ethereum
    address public immutable remoteToken;

    /// @notice Address of the bridge in fraxtal
    address public immutable bridge;

    /// @notice Address of the owner
    address public owner;

    /// @notice Mapping of enabled operators
    mapping(address => bool) public operators;

    /// @notice Throwed when a low level call fails
    error CallFailed();

    /// @notice Throwed on Auth
    error OnlyOwner();

    /// @notice Throwed on Auth
    error OnlyOperator();

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert OnlyOperator();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _bridge,
        address _remoteToken,
        address _delegationRegistry,
        address _initialDelegate
    ) ERC20(_name, _symbol) {
        owner = msg.sender;
        remoteToken = _remoteToken;
        bridge = _bridge;

        // Custom code for Fraxtal
        // set _initialDelegate as delegate
        (bool success,) =
            _delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", _initialDelegate));
        if (!success) revert CallFailed();
        // disable self managing delegation
        (success,) = _delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        if (!success) revert CallFailed();
    }

    /// @notice Toggle an operator that can mint and burn sdToken
    /// @param _operator new operator address
    function toggleOperator(address _operator) external onlyOwner {
        operators[_operator] = !operators[_operator];
    }

    /// @notice Revoke the ownership
    function revokeOwnnership() external onlyOwner {
        owner = address(0);
    }

    /// @notice mint new sdToken, callable only by the operator
    /// @param _to recipient to mint for
    /// @param _amount amount to mint
    function mint(address _to, uint256 _amount) external onlyOperator {
        _mint(_to, _amount);
    }

    /// @notice Burn sdToken, callable only by the operator
    /// @param _from sdToken holder
    /// @param _amount amount to burn
    function burn(address _from, uint256 _amount) external onlyOperator {
        _burn(_from, _amount);
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
