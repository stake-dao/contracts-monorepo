// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/src/Test.sol";
import {MultiCumulativeMerkleDrop} from "src/common/MultiCumulativeMerkleDrop.sol";
import {MockMultiCumulativeMerkleDrop} from "test/common/mocks/Mocks.sol";
import {MockERC20} from "test/common/mocks/Mocks.sol";
import {Utils} from "test/common/utils/Utils.sol";

contract MultiCumulativeMerkleDropTest is Test, Utils {
    MockMultiCumulativeMerkleDrop private merkleDropContract;

    address private constant GOVERNANCE = address(0x1234);
    address private constant USER_1 = address(0xABCD);
    address private constant USER_2 = address(0xABBB);
    address private constant USER_3 = address(0xCCCC);
    address private constant ALLOWED_ADDRESS = address(0xBABA);

    MockERC20 private token1;
    MockERC20 private token2;

    bytes32 private merkleRoot1;
    bytes32 private merkleRoot2;

    function setUp() external {
        merkleDropContract = new MockMultiCumulativeMerkleDrop(GOVERNANCE);

        // Deploy mock ERC20 tokens
        token1 = new MockERC20("Token1", "TKN1", 18);
        token2 = new MockERC20("Token2", "TKN2", 18);

        // Set up initial state
        vm.startPrank(GOVERNANCE);
        merkleDropContract.allowAddress(ALLOWED_ADDRESS);
        vm.stopPrank();

        // Mint tokens to the contract
        token1.mint(address(merkleDropContract), 1000 ether);
        token2.mint(address(merkleDropContract), 500 ether);
    }

    function testInitialState() public view {
        assertEq(merkleDropContract.governance(), GOVERNANCE);
        assertTrue(merkleDropContract.allowed(ALLOWED_ADDRESS));
        assertTrue(merkleDropContract.isFrozen(address(token1)));
        assertTrue(merkleDropContract.isFrozen(address(token2)));
        assertEq(merkleDropContract.getMerkleRoot(address(token1)), bytes32(0));
        assertEq(merkleDropContract.getMerkleRoot(address(token2)), bytes32(0));
    }

    function testSetMerkleRoot() public {
        bytes32 newRoot = keccak256("new root");
        vm.prank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), newRoot);
        assertEq(merkleDropContract.getMerkleRoot(address(token1)), newRoot);
    }

    function testMultipleClaims() public {
        // First distribution
        string[] memory userAddresses = new string[](2);
        string[] memory amounts = new string[](2);

        userAddresses[0] = vm.toString(USER_1);
        userAddresses[1] = vm.toString(USER_2);

        amounts[0] = "100";
        amounts[1] = "200";

        generateMerkleProof(userAddresses, amounts);

        (address[] memory addresses, uint256[] memory claimAmounts, bytes32[][] memory proofs) = getMerkleJSONData();

        (bytes32 root1, uint256 total1) = getMerkleRootAndTotal();

        // Set merkle root for token1
        vm.prank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), root1);

        // Claim for USER_1
        vm.prank(USER_1);
        merkleDropContract.claim(address(token1), USER_1, claimAmounts[0], proofs[0]);
        assertEq(token1.balanceOf(USER_1), 100 ether);

        // Second distribution (double the amounts)
        amounts[0] = "200";
        amounts[1] = "400";

        generateMerkleProof(userAddresses, amounts);

        (addresses, claimAmounts, proofs) = getMerkleJSONData();

        (bytes32 root2, uint256 total2) = getMerkleRootAndTotal();

        // Set new merkle root for token1
        vm.prank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), root2);

        // Claim for USER_1 (should only receive additional 100)
        vm.prank(USER_1);
        merkleDropContract.claim(address(token1), USER_1, claimAmounts[0], proofs[0]);
        assertEq(token1.balanceOf(USER_1), 200 ether);

        // Claim for USER_2 (should receive full 400)
        vm.prank(USER_2);
        merkleDropContract.claim(address(token1), USER_2, claimAmounts[1], proofs[1]);
        assertEq(token1.balanceOf(USER_2), 400 ether);

        // Attempt to claim again (should revert)
        vm.prank(USER_1);
        vm.expectRevert(MultiCumulativeMerkleDrop.NothingToClaim.selector);
        merkleDropContract.claim(address(token1), USER_1, claimAmounts[0], proofs[0]);

        vm.prank(USER_2);
        vm.expectRevert(MultiCumulativeMerkleDrop.NothingToClaim.selector);
        merkleDropContract.claim(address(token1), USER_2, claimAmounts[1], proofs[1]);
    }

    function testFreeze() public {
        vm.startPrank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), keccak256("root1"));
        merkleDropContract.freeze(address(token1));
        assertTrue(merkleDropContract.isFrozen(address(token1)));
        vm.stopPrank();

        // Attempt to claim after freezing
        vm.prank(USER_1);
        vm.expectRevert(MultiCumulativeMerkleDrop.Frozen.selector);
        merkleDropContract.claim(address(token1), USER_1, 100, new bytes32[](0));
    }

    function testMultiFreeze() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        bytes32[] memory roots = new bytes32[](2);
        roots[0] = keccak256("root1");
        roots[1] = keccak256("root2");

        vm.startPrank(GOVERNANCE);
        merkleDropContract.multiSetMerkleRoot(tokens, roots);
        merkleDropContract.multiFreeze(tokens);
        vm.stopPrank();

        assertTrue(merkleDropContract.isFrozen(address(token1)));
        assertTrue(merkleDropContract.isFrozen(address(token2)));
    }

    function testAllowDisallowAddress() public {
        address newAllowedAddress = address(0xBEEF);

        vm.prank(GOVERNANCE);
        merkleDropContract.allowAddress(newAllowedAddress);
        assertTrue(merkleDropContract.allowed(newAllowedAddress));

        vm.prank(GOVERNANCE);
        merkleDropContract.disallowAddress(newAllowedAddress);
        assertFalse(merkleDropContract.allowed(newAllowedAddress));
    }

    function testTransferGovernance() public {
        address newGovernance = address(0xDEAD);

        vm.prank(GOVERNANCE);
        merkleDropContract.transferGovernance(newGovernance);

        vm.prank(newGovernance);
        merkleDropContract.acceptGovernance();

        assertEq(merkleDropContract.governance(), newGovernance);
    }

    function testCannotClaimMoreThanAllowed() public {
        string[] memory userAddresses = new string[](1);
        string[] memory amounts = new string[](1);

        userAddresses[0] = vm.toString(USER_1);
        amounts[0] = "100";

        generateMerkleProof(userAddresses, amounts);

        (address[] memory addresses, uint256[] memory claimAmounts, bytes32[][] memory proofs) = getMerkleJSONData();

        (bytes32 root, uint256 total) = getMerkleRootAndTotal();

        vm.startPrank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), root);
        vm.stopPrank();

        vm.prank(USER_1);
        vm.expectRevert(MultiCumulativeMerkleDrop.InvalidProof.selector);
        merkleDropContract.claim(address(token1), USER_1, claimAmounts[0] + 1 ether, proofs[0]);
    }

    function testSetWrongMerkleRootReverts() public {
        bytes32 wrongRoot = keccak256("wrong root");

        vm.prank(ALLOWED_ADDRESS);
        merkleDropContract.setMerkleRoot(address(token1), wrongRoot);

        string[] memory userAddresses = new string[](1);
        string[] memory amounts = new string[](1);

        userAddresses[0] = vm.toString(USER_1);
        amounts[0] = "100";

        generateMerkleProof(userAddresses, amounts);

        (address[] memory addresses, uint256[] memory claimAmounts, bytes32[][] memory proofs) = getMerkleJSONData();

        vm.prank(USER_1);
        vm.expectRevert(MultiCumulativeMerkleDrop.InvalidProof.selector);
        merkleDropContract.claim(address(token1), USER_1, claimAmounts[0], proofs[0]);
    }

    function testClaimForAnotherAccount() public {
        string[] memory userAddresses = new string[](1);
        string[] memory amounts = new string[](1);

        userAddresses[0] = vm.toString(USER_1);
        amounts[0] = "100";

        generateMerkleProof(userAddresses, amounts);

        (address[] memory addresses, uint256[] memory claimAmounts, bytes32[][] memory proofs) = getMerkleJSONData();

        (bytes32 root, uint256 total) = getMerkleRootAndTotal();

        vm.startPrank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), root);
        vm.stopPrank();

        // USER_2 claims for USER_1
        vm.prank(USER_2);
        merkleDropContract.claim(address(token1), USER_1, claimAmounts[0], proofs[0]);

        // Check that USER_1 received the tokens
        assertEq(token1.balanceOf(USER_1), 100 ether);
        assertEq(token1.balanceOf(USER_2), 0);
    }

    function testCannotClaimTwice() public {
        string[] memory userAddresses = new string[](1);
        string[] memory amounts = new string[](1);

        userAddresses[0] = vm.toString(USER_1);
        amounts[0] = "100";

        generateMerkleProof(userAddresses, amounts);

        (, uint256[] memory claimAmounts, bytes32[][] memory proofs) = getMerkleJSONData();

        (bytes32 root, uint256 total) = getMerkleRootAndTotal();

        vm.startPrank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), root);
        vm.stopPrank();

        vm.prank(USER_1);
        merkleDropContract.claim(address(token1), USER_1, claimAmounts[0], proofs[0]);

        vm.prank(USER_1);
        vm.expectRevert(MultiCumulativeMerkleDrop.NothingToClaim.selector);
        merkleDropContract.claim(address(token1), USER_1, claimAmounts[0], proofs[0]);
    }

    function testMultiSetMerkleRoot() public {
        address[] memory tokens = new address[](2);
        bytes32[] memory roots = new bytes32[](2);

        tokens[0] = address(token1);
        tokens[1] = address(token2);
        roots[0] = keccak256("root1");
        roots[1] = keccak256("root2");

        vm.startPrank(GOVERNANCE);
        merkleDropContract.multiSetMerkleRoot(tokens, roots);
        vm.stopPrank();

        assertEq(merkleDropContract.getMerkleRoot(address(token1)), roots[0]);
        assertEq(merkleDropContract.getMerkleRoot(address(token2)), roots[1]);
    }

    function testSetRecipientAndClaim() public {
        string[] memory userAddresses = new string[](1);
        string[] memory amounts = new string[](1);

        userAddresses[0] = vm.toString(USER_1);
        amounts[0] = "100";

        generateMerkleProof(userAddresses, amounts);

        (, uint256[] memory claimAmounts, bytes32[][] memory proofs) = getMerkleJSONData();

        (bytes32 root, uint256 total) = getMerkleRootAndTotal();

        vm.startPrank(GOVERNANCE);
        merkleDropContract.setMerkleRoot(address(token1), root);

        // Set USER_2 as the recipient for USER_1
        merkleDropContract.setRecipient(USER_1, USER_2);
        vm.stopPrank();

        // Verify that the recipient is set correctly
        assertEq(merkleDropContract.recipients(USER_1), USER_2);

        // USER_1 claims, but tokens should go to USER_2
        vm.prank(USER_1);
        merkleDropContract.claim(address(token1), USER_1, claimAmounts[0], proofs[0]);

        // Check that USER_2 received the tokens instead of USER_1
        assertEq(token1.balanceOf(USER_1), 0);
        assertEq(token1.balanceOf(USER_2), 100 ether);

        // Verify that the claim is recorded for USER_1
        assertEq(merkleDropContract.getCumulativeClaimed(address(token1), USER_1), 100 ether);
    }
}
