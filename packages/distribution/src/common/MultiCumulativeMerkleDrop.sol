// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {console} from "forge-std/src/console.sol";

/// @title MultiCumulativeMerkleDrop
/// @notice A multi-token merkle tree based distribution contract with cumulative claiming mechanism
/// @dev Inspired by https://github.com/1inch/merkle-distribution/blob/master/contracts/CumulativeMerkleDrop.sol
/// @dev Abstracted to be inherited for name and version
abstract contract MultiCumulativeMerkleDrop {
    using SafeTransferLib for ERC20;

    /// @notice Merkle root for each token
    mapping(address => bytes32) public merkleRoots;

    /// @notice Cumulative amount claimed by each account for each token
    mapping(address => mapping(address => uint256)) public cumulativeClaimed;

    /// @notice Address of the governance
    address public governance;

    /// @notice Address of the future governance
    address public futureGovernance;

    /// @notice Take trace of allowed address
    mapping(address => bool) public allowed;

    /// @notice Emitted when the merkle root is updated
    event MerkleRootUpdated(
        address indexed token,
        bytes32 oldMerkleRoot,
        bytes32 newMerkleRoot
    );

    /// @notice Emitted when a successful claim is made
    event Claimed(
        address indexed token,
        address indexed account,
        uint256 amount
    );

    /// @notice Emitted when an address is allowed to set the merkle
    event Allowed(address _addr);

    /// @notice Emitted when an address is disallowed to set the merkle
    event Disallowed(address _addr);

    /// @notice Emitted when the governance changes
    event GovernanceChanged(address _governance);

    /// @notice Emitted when a token is frozen
    event Freeze(address indexed token);

    /// @notice Thrown when the token is frozen
    error Frozen();

    /// @notice Thrown when the provided proof is invalid
    error InvalidProof();

    /// @notice Thrown when there's nothing to claim
    error NothingToClaim();

    /// @notice Thrown when the merkle root has been updated
    error MerkleRootWasUpdated();

    /// @notice Thrown on unauthorized access
    error Auth();

    /// @notice Thrown on not allowed address
    error NotAllowed();

    /// @notice Thrown if an address is already allowed
    error AlreadyAllowed();

    /// @notice Thrown when the token is already frozen
    error AlreadyFrozen();

    /// @notice only governance
    modifier onlyGovernance() {
        if (msg.sender != governance) revert Auth();
        _;
    }

    /// @notice only governance or allowed
    modifier onlyGovernanceOrAllowed() {
        if (!allowed[msg.sender] && msg.sender != governance) {
            revert NotAllowed();
        }
        _;
    }

    constructor(address _governance) {
        governance = _governance;
    }

    /// @notice Set a new merkle root for a token
    /// @param token The token address
    /// @param newMerkleRoot The new merkle root to set
    function setMerkleRoot(
        address token,
        bytes32 newMerkleRoot
    ) external onlyGovernanceOrAllowed {
        require(isFrozen(token), "Not frozen");
        emit MerkleRootUpdated(token, merkleRoots[token], newMerkleRoot);
        merkleRoots[token] = newMerkleRoot;
    }

    /// @notice Set new merkle roots for multiple tokens
    /// @param tokens Array of token addresses
    /// @param newMerkleRoots Array of new merkle roots to set
    function multiSetMerkleRoot(
        address[] calldata tokens,
        bytes32[] calldata newMerkleRoots
    ) external onlyGovernanceOrAllowed {
        require(tokens.length == newMerkleRoots.length, "Length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            require(isFrozen(tokens[i]), "Not frozen");
            emit MerkleRootUpdated(
                tokens[i],
                merkleRoots[tokens[i]],
                newMerkleRoots[i]
            );
            merkleRoots[tokens[i]] = newMerkleRoots[i];
        }
    }

    /// @notice Claim tokens for an account
    /// @param token The token address
    /// @param account The account to claim for
    /// @param cumulativeAmount The total amount claimable for the account
    /// @param merkleProof The merkle proof for the claim
    function claim(
        address token,
        address account,
        uint256 cumulativeAmount,
        bytes32[] calldata merkleProof
    ) external {
        if (isFrozen(token)) revert Frozen();

        console.log("Claiming for token:", token);
        console.log("Account:", account);
        console.log("Cumulative Amount:", cumulativeAmount);
        console.log("Merkle Root:");
        console.logBytes32(merkleRoots[token]);

        bytes32 leaf = keccak256(abi.encodePacked(account, cumulativeAmount));

        console.log("Leaf:");
        console.logBytes32(leaf);

        for (uint i = 0; i < merkleProof.length; i++) {
            console.log("Proof element:");
            console.logBytes32(merkleProof[i]);
        }

        if (!MerkleProofLib.verify(merkleProof, merkleRoots[token], leaf)) {
            revert InvalidProof();
        }

        uint256 preclaimed = cumulativeClaimed[token][account];
        if (preclaimed >= cumulativeAmount) revert NothingToClaim();

        cumulativeClaimed[token][account] = cumulativeAmount;

        unchecked {
            uint256 amount = cumulativeAmount - preclaimed;
            SafeTransferLib.safeTransfer(token, account, amount);
            emit Claimed(token, account, amount);
        }
    }

    /// @notice Freeze a token by setting its merkle root to 0
    /// @param token The token address to freeze
    function freeze(address token) external onlyGovernanceOrAllowed {
        if (isFrozen(token)) revert AlreadyFrozen();
        emit MerkleRootUpdated(token, merkleRoots[token], bytes32(0));
        merkleRoots[token] = bytes32(0);
        emit Freeze(token);
    }

    function multiFreeze(address[] calldata tokens) external onlyGovernance {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (isFrozen(tokens[i])) revert AlreadyFrozen();
            emit MerkleRootUpdated(
                tokens[i],
                merkleRoots[tokens[i]],
                bytes32(0)
            );
            merkleRoots[tokens[i]] = bytes32(0);
            emit Freeze(tokens[i]);
        }
    }

    /// @notice Allow an address to set the merkle
    /// @param _addr Address to allow
    function allowAddress(address _addr) external onlyGovernance {
        if (allowed[_addr]) revert AlreadyAllowed();
        allowed[_addr] = true;
        emit Allowed(_addr);
    }

    /// @notice Disallow an address to set the merkle
    /// @param _addr Address to disallow
    function disallowAddress(address _addr) external onlyGovernance {
        if (!allowed[_addr]) revert NotAllowed();
        allowed[_addr] = false;
        emit Disallowed(_addr);
    }

    /// @notice Transfer the governance to a new address
    /// @param _governance Address of the new governance
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert Auth();
        governance = msg.sender;
        futureGovernance = address(0);
        emit GovernanceChanged(msg.sender);
    }

    /// @notice Check if a token is frozen (merkle root is 0)
    /// @param token The token address to check
    /// @return bool True if the token is frozen, false otherwise
    function isFrozen(address token) public view returns (bool) {
        return merkleRoots[token] == bytes32(0);
    }

    /// @notice Get the current merkle root for a token
    /// @param token The token address
    /// @return bytes32 The current merkle root for the token
    function getMerkleRoot(address token) external view returns (bytes32) {
        return merkleRoots[token];
    }

    /// @notice Get the cumulative claimed amount for an account and token
    /// @param token The token address
    /// @param account The account to check
    /// @return uint256 The cumulative claimed amount
    function getCumulativeClaimed(
        address token,
        address account
    ) external view returns (uint256) {
        return cumulativeClaimed[token][account];
    }

    function name() external virtual returns (string memory);

    function version() external virtual returns (string memory);
}
