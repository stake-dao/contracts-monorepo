// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";
import {vlCVXMultiMerkleDrop} from "src/mainnet/vlCVXMultiMerkleDrop.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {Utils} from "./Utils.sol";

contract MultiCumulativeMerkleDropTest is Test, Utils {
    vlCVXMultiMerkleDrop private merkleDropContract;

    address private constant GOVERNANCE = address(0x1234);
    address private constant USER_1 = address(0xABCD);
    address private constant USER_2 = address(0xABBB);
    address private constant ALLOWED_ADDRESS = address(0xBABA);

    MockERC20 private token1;
    MockERC20 private token2;

    bytes32 private merkleRoot1;
    bytes32 private merkleRoot2;

    uint256 private amount1;
    uint256 private amount2;

    bytes32[] private user1Proof1;
    bytes32[] private user2Proof1;
    bytes32[] private user1Proof2;
    bytes32[] private user2Proof2;

    function setUp() external {
        merkleDropContract = new vlCVXMultiMerkleDrop(GOVERNANCE);

        // Deploy mock ERC20 tokens
        token1 = new MockERC20("Token1", "TKN1", 18);
        token2 = new MockERC20("Token2", "TKN2", 18);

        // Set up initial state
        vm.startPrank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), merkleRoot1);
        merkleDropContract.setMerkleRoot(address(token2), merkleRoot2);
        merkleDropContract.allowAddress(ALLOWED_ADDRESS);
        vm.stopPrank();

        // Mint tokens to the contract
        token1.mint(address(merkleDropContract), 100000000000000000000000000000000000000);
        token2.mint(address(merkleDropContract), 100000000000000000000000000000000000000);
    }

    function testComputeRoot() public {
        bytes32 leaf0 = 0xcf64e9f628e0a4a0b1ba02498d291411dfbab25e185c572cd8b717262ddebd32;
        bytes32 leaf1 = 0x3e15b7f277ba169794519242f9fcc32bc03d965ec4b7b37e9ffc5c93fefd25f9;

        bytes32 computedRoot;
        if (leaf0 < leaf1) {
            computedRoot = keccak256(abi.encodePacked(leaf0, leaf1));
        } else {
            computedRoot = keccak256(abi.encodePacked(leaf1, leaf0));
        }

        bytes32 expectedRoot = 0x47e0936914bbeebf6fa367f80c2889b614ef9303bfa106e25070d4b712009dc4;

        console.log("Computed Root:", uint256(computedRoot));
        console.log("Expected Root:", uint256(expectedRoot));
        console.log("Roots match:", computedRoot == expectedRoot);
    }

    function testClaim() public {
        // Generate Merkle tree for token1
        string[] memory userAddresses = new string[](2);
        string[] memory amounts = new string[](2);

        userAddresses[0] = vm.toString(USER_1);
        userAddresses[1] = vm.toString(USER_2);

        amounts[0] = "100000000000000000000"; // 100 ether
        amounts[1] = "200000000000000000000"; // 200 ether

        generateMerkleProof(userAddresses, amounts);

        (
            address[] memory addresses,
            uint256[] memory claimAmounts,
            bytes32[][] memory proofs
        ) = getMerkleJSONData();

        (bytes32 root, uint256 total) = getMerkleRootAndTotal();

        // Set merkle root for token1
        vm.prank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), root);

        // Claim for USER_1
        vm.prank(USER_1);
        merkleDropContract.claim(
            address(token1),
            USER_1,
            claimAmounts[0],
            proofs[0]
        );
        assertEq(token1.balanceOf(USER_1), claimAmounts[0]);

        /*
        // Claim for USER_2
        vm.prank(USER_2);
        merkleDropContract.claim(address(token1), USER_2, claimAmounts[1], proofs[1]);
        assertEq(token1.balanceOf(USER_2), claimAmounts[1]);
        */

        // Generate Merkle tree for token2
        /*
        amounts[0] = "150";
        amounts[1] = "250";

        generateMerkleProof(userAddresses, amounts);

        (addresses, claimAmounts, proofs) = getMerkleJSONData();
        (root, total) = getMerkleRootAndTotal();

        // Set merkle root for token2
        vm.prank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token2), root);

        // Claim for USER_1
        vm.prank(USER_1);
        merkleDropContract.claim(address(token2), USER_1, claimAmounts[0], proofs[0]);
        assertEq(token2.balanceOf(USER_1), claimAmounts[0]);

        // Claim for USER_2
        vm.prank(USER_2);
        merkleDropContract.claim(address(token2), USER_2, claimAmounts[1], proofs[1]);
        assertEq(token2.balanceOf(USER_2), claimAmounts[1]);
        */
    }
}

contract MockERC20 is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
